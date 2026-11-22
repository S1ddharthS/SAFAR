import csv
import io
from datetime import date

from sqlalchemy.orm import Session

from app.models import Expense, ExpenseParticipant, Trip, TripMember, User


def active_member_users(db: Session, trip: Trip) -> list[User]:
    members = (
        db.query(TripMember)
        .filter(TripMember.trip_id == trip.id, TripMember.status == "active")
        .all()
    )
    user_ids = [member.user_id for member in members if member.user_id]
    if not user_ids:
        return []
    return db.query(User).filter(User.id.in_(user_ids)).all()


def resolve_shares(
    amount: float,
    participants: list[dict],
    split: str,
) -> list[dict]:
    """Return participants with normalised share_amount values.

    Raises ValueError when custom shares do not reconcile exactly.
    """
    cleaned = [
        {
            "user_id": participant.get("user_id"),
            "guest_name": participant.get("guest_name"),
            "weight": max(0.01, float(participant.get("weight") or 1)),
            "share_amount": participant.get("share_amount"),
        }
        for participant in participants
    ]
    if not cleaned:
        raise ValueError("At least one participant is required.")

    if split == "custom":
        total = 0.0
        for participant in cleaned:
            if participant["share_amount"] is None:
                raise ValueError("Custom split requires a share for every participant.")
            participant["share_amount"] = round(float(participant["share_amount"]), 2)
            total += participant["share_amount"]
        if abs(total - amount) > 0.01:
            raise ValueError(
                f"Custom shares total {total:.2f}, which does not match the expense amount {amount:.2f}."
            )
        return cleaned

    if split == "weights":
        weight_sum = sum(participant["weight"] for participant in cleaned)
        running = 0.0
        for index, participant in enumerate(cleaned):
            if index == len(cleaned) - 1:
                participant["share_amount"] = round(amount - running, 2)
            else:
                share = round(amount * participant["weight"] / weight_sum, 2)
                participant["share_amount"] = share
                running += share
        return cleaned

    count = len(cleaned)
    base = round(amount / count, 2)
    running = 0.0
    for index, participant in enumerate(cleaned):
        if index == count - 1:
            participant["share_amount"] = round(amount - running, 2)
        else:
            participant["share_amount"] = base
            running += base
    return cleaned


def participant_rows(db: Session, expense_id: str) -> list[ExpenseParticipant]:
    return (
        db.query(ExpenseParticipant)
        .filter(ExpenseParticipant.expense_id == expense_id)
        .all()
    )


def balances(db: Session, trip: Trip) -> dict:
    expenses = (
        db.query(Expense)
        .filter(Expense.trip_id == trip.id, Expense.deleted_at.is_(None))
        .all()
    )
    net: dict[str, float] = {}
    spent_total = 0.0
    for expense in expenses:
        spent_total += expense.amount
        net[expense.paid_by] = round(net.get(expense.paid_by, 0.0) + expense.amount, 2)
        for row in participant_rows(db, expense.id):
            if row.user_id:
                net[row.user_id] = round(net.get(row.user_id, 0.0) - row.share_amount, 2)

    user_ids = (
        db.query(TripMember.user_id)
        .filter(
            TripMember.trip_id == trip.id,
            TripMember.status == "active",
            TripMember.user_id.isnot(None),
        )
        .all()
    )
    ids = [row[0] for row in user_ids]
    users = db.query(User).filter(User.id.in_(ids)).all() if ids else []
    names = {user.id: user.display_name for user in users}
    for user_id in ids:
        net.setdefault(user_id, 0.0)

    creditors = sorted(
        [(uid, amt) for uid, amt in net.items() if amt > 0.01],
        key=lambda item: item[1],
        reverse=True,
    )
    debtors = sorted(
        [(uid, -amt) for uid, amt in net.items() if amt < -0.01],
        key=lambda item: item[1],
        reverse=True,
    )
    settlements = []
    creditors = [list(item) for item in creditors]
    debtors = [list(item) for item in debtors]
    ci = di = 0
    while ci < len(creditors) and di < len(debtors):
        amount = min(creditors[ci][1], debtors[di][1])
        if amount > 0.01:
            settlements.append(
                {
                    "from_user_id": debtors[di][0],
                    "from_name": names.get(debtors[di][0], "Member"),
                    "to_user_id": creditors[ci][0],
                    "to_name": names.get(creditors[ci][0], "Member"),
                    "amount": round(amount, 2),
                }
            )
        creditors[ci][1] -= amount
        debtors[di][1] -= amount
        if creditors[ci][1] <= 0.01:
            ci += 1
        if debtors[di][1] <= 0.01:
            di += 1

    return {
        "total_spent": round(spent_total, 2),
        "currency": trip.currency,
        "balances": [
            {
                "user_id": user_id,
                "display_name": names.get(user_id, "Member"),
                "net": round(net.get(user_id, 0.0), 2),
            }
            for user_id in sorted(net, key=lambda uid: net[uid], reverse=True)
        ],
        "settlements": [
            {**settlement, "status": "suggested"} for settlement in settlements
        ],
        "disclosure": "Tracking only — SAFAR does not move money.",
    }


def expenses_csv(db: Session, trip: Trip) -> str:
    buffer = io.StringIO()
    writer = csv.writer(buffer)
    writer.writerow(
        ["date", "title", "category", "amount", "currency", "paid_by", "participants"]
    )
    expenses = (
        db.query(Expense)
        .filter(Expense.trip_id == trip.id, Expense.deleted_at.is_(None))
        .order_by(Expense.incurred_on, Expense.created_at)
        .all()
    )
    users = {user.id: user.display_name for user in active_member_users(db, trip)}
    for expense in expenses:
        rows = participant_rows(db, expense.id)
        parts = ", ".join(
            f"{(users.get(row.user_id) or row.guest_name or 'Guest')} {row.share_amount:.2f}"
            for row in rows
        )
        writer.writerow(
            [
                expense.incurred_on.isoformat() if isinstance(expense.incurred_on, date) else expense.incurred_on,
                expense.title,
                expense.category,
                f"{expense.amount:.2f}",
                expense.currency,
                users.get(expense.paid_by, expense.paid_by),
                parts,
            ]
        )
    return buffer.getvalue()
