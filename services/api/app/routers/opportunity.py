from datetime import date

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session

from app.core.deps import (
    get_current_user,
    get_db,
    get_trip_and_member,
    trip_scope_guard,
)
from app.models import User
from app.services.opportunity import clock

router = APIRouter(
    prefix="/api/trips",
    tags=["opportunity"],
    dependencies=[Depends(trip_scope_guard)],
)


@router.get("/{trip_id}/opportunity-clock")
def opportunity_clock(
    trip_id: str,
    on: date | None = Query(default=None),
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    trip, _member = get_trip_and_member(trip_id, db, user)
    target = on or (date.today() if trip.start_date <= date.today() <= trip.end_date else trip.start_date)
    if target < trip.start_date or target > trip.end_date:
        raise HTTPException(
            status_code=422,
            detail="Chosen date is outside this trip's dates",
        )
    return clock(db, trip, target)
