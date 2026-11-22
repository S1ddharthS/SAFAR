"""Group expenses, balances and settlement suggestions (F13)."""

from datetime import date

from fastapi import APIRouter, Depends, HTTPException, Query, Response
from sqlalchemy.orm import Session

from app.core.deps import (
    get_current_user,
    get_db,
    get_trip_and_member,
    trip_scope_guard,
)
from app.core.realtime import manager
from app.models import Expense, ExpenseParticipant, TripMember, User
from app.models.models import utcnow
from app.schemas.schemas import ExpenseCreate
from app.services import expenses as expense_service
from app.services.common import audit, event_payload, notify_trip_members
from app.services.serializers import expense_out

router = APIRouter(
    prefix="/api/trips",
    tags=["expenses"],
    dependencies=[Depends(trip_scope_guard)],
)

ADMIN_ROLES = {"owner", "admin"}


def _trip(db, trip_id, user, roles=None):
    return get_trip_and_member(trip_id, db, user, roles)


def _member_user_ids(db: Session, trip_id: str) -> set[str]:
    rows = (
        db.query(TripMember.user_id)
        .filter(
            TripMember.trip_id == trip_id,
            TripMember.status == "active",
            TripMember.user_id.isnot(None),
        )
        .all()
    )
    return {row[0] for row in rows}


def _serialize(db: Session, expenses: list[Expense]) -> list[dict]:
    return [
        expense_out(db, expense, expense_service.participant_rows(db, expense.id))
        for expense in expenses
    ]


@router.get("/{trip_id}/expenses")
def list_expenses(
    trip_id: str,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    trip, _member = _trip(db, trip_id, user)
    rows = (
        db.query(Expense)
        .filter(Expense.trip_id == trip.id, Expense.deleted_at.is_(None))
        .order_by(Expense.incurred_on.desc(), Expense.created_at.desc())
        .all()
    )
    data = _serialize(db, rows)
    return {
        "items": data,
        "totals": {
            "spent": round(sum(expense.amount for expense in rows), 2),
            "count": len(rows),
            "currency": trip.currency,
            "trip_budget": trip.budget_total,
            "remaining": (
                round(trip.budget_total - sum(expense.amount for expense in rows), 2)
                if trip.budget_total
                else None
            ),
        },
    }


@router.post("/{trip_id}/expenses", status_code=201)
async def create_expense(
    trip_id: str,
    payload: ExpenseCreate,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    trip, _member = _trip(db, trip_id, user)
    if payload.currency and payload.currency != trip.currency:
        raise HTTPException(
            status_code=422,
            detail=f"Expenses must use the trip currency ({trip.currency}).",
        )
    payer = payload.paid_by or user.id
    active_ids = _member_user_ids(db, trip.id)
    if payer not in active_ids:
        raise HTTPException(status_code=422, detail="The payer must be an active trip member")

    participants = [
        participant.model_dump() for participant in payload.participants
    ]
    if not participants:
        participants = [
            {"user_id": member_id, "weight": 1.0, "share_amount": None}
            for member_id in active_ids
        ]
    for participant in participants:
        participant_id = participant.get("user_id")
        if participant_id and participant_id not in active_ids:
            raise HTTPException(
                status_code=422,
                detail="Every participating user must be an active trip member",
            )
        if not participant_id and not participant.get("guest_name"):
            raise HTTPException(
                status_code=422,
                detail="A participant needs either a member or a guest name",
            )

    try:
        resolved = expense_service.resolve_shares(payload.amount, participants, payload.split)
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc))

    expense = Expense(
        trip_id=trip.id,
        title=payload.title,
        category=payload.category,
        amount=payload.amount,
        currency=trip.currency,
        paid_by=payer,
        incurred_on=payload.incurred_on or date.today(),
        notes=payload.notes,
        created_by=user.id,
    )
    db.add(expense)
    db.flush()
    for participant in resolved:
        db.add(
            ExpenseParticipant(
                expense_id=expense.id,
                user_id=participant.get("user_id"),
                guest_name=participant.get("guest_name"),
                weight=participant["weight"],
                share_amount=participant["share_amount"],
            )
        )
    audit(
        db,
        action="expense.create",
        entity_type="expense",
        entity_id=expense.id,
        user_id=user.id,
        trip_id=trip.id,
        detail={"amount": expense.amount, "category": expense.category},
    )
    notify_trip_members(
        db,
        trip,
        kind="expense_added",
        title=f"New expense: {expense.title}",
        body=f"{expense.amount:.2f} {expense.currency} paid by {user.display_name}.",
        link=f"/trips/{trip.id}/expenses",
        exclude_user_id=user.id,
    )
    db.commit()
    await manager.broadcast(
        trip.id, event_payload("expenses.updated", trip_id=trip.id)
    )
    return expense_out(db, expense, expense_service.participant_rows(db, expense.id))


@router.delete("/{trip_id}/expenses/{expense_id}")
async def delete_expense(
    trip_id: str,
    expense_id: str,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    trip, member = _trip(db, trip_id, user)
    expense = db.get(Expense, expense_id)
    if not expense or expense.trip_id != trip.id or expense.deleted_at is not None:
        raise HTTPException(status_code=404, detail="Expense not found")
    if expense.created_by != user.id and member.role not in ADMIN_ROLES:
        raise HTTPException(
            status_code=403, detail="Only the author or a trip admin can delete an expense"
        )
    expense.deleted_at = utcnow()
    audit(
        db,
        action="expense.delete",
        entity_type="expense",
        entity_id=expense.id,
        user_id=user.id,
        trip_id=trip.id,
    )
    db.commit()
    await manager.broadcast(
        trip.id, event_payload("expenses.updated", trip_id=trip.id)
    )
    return {"ok": True, "note": "Removed from balances and settlement suggestions."}


@router.get("/{trip_id}/expenses/balances")
def get_balances(
    trip_id: str,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    trip, _member = _trip(db, trip_id, user)
    return expense_service.balances(db, trip)


@router.get("/{trip_id}/expenses/export")
def export_expenses(
    trip_id: str,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    trip, _member = _trip(db, trip_id, user)
    csv_body = expense_service.expenses_csv(db, trip)
    safe_name = "".join(
        character if character.isalnum() or character in "-_" else "-"
        for character in trip.name.lower()
    ).strip("-") or "trip"
    return Response(
        content=csv_body,
        media_type="text/csv; charset=utf-8",
        headers={
            "Content-Disposition": f'attachment; filename="{safe_name}-expenses.csv"'
        },
    )
