"""Request and response shapes (the API contract).

Pydantic checks every incoming request against these classes. If a field is
missing or has a wrong value, FastAPI automatically returns HTTP 422.
"""

from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field

Priority = Literal["low", "normal", "high"]
Status = Literal["open", "in_progress", "closed"]


class TicketCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    subject: str = Field(min_length=1, max_length=200)
    description: str = Field(min_length=1, max_length=5000)
    priority: Priority


class TicketStatusUpdate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    status: Status


class TicketOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    subject: str
    description: str
    priority: Priority
    status: Status
    created_at: datetime
    updated_at: datetime


class TicketPage(BaseModel):
    items: list[TicketOut]
    limit: int
    offset: int
    total: int
