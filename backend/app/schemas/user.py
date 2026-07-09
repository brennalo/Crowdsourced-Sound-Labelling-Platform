from pydantic import BaseModel, EmailStr
from datetime import datetime
from typing import Literal
import uuid


class UserRegister(BaseModel):
    email: EmailStr
    password: str
    display_name: str | None = None
    role: Literal["contributor", "researcher"] = "contributor"


class UserLogin(BaseModel):
    email: EmailStr
    password: str


class UserOut(BaseModel):
    id: uuid.UUID
    email: str
    display_name: str | None
    role: str
    created_at: datetime

    model_config = {"from_attributes": True}


class TokenOut(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user: UserOut
