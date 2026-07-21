from pydantic import BaseModel
from typing import Literal


class DeviceTokenRegister(BaseModel):
    token: str
    platform: Literal["android", "ios"] | None = None


class DeviceTokenUnregister(BaseModel):
    token: str
