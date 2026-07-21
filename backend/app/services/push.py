# Programmer Name : Brenna Lo
# Program Name : push.py
# Description : Push notification functionality via Firebase Cloud Messaging
# First Written on : 2024-06-10
# Edited on : 2024-07-18

"""
Push notifications via Firebase Cloud Messaging.

Design: every push is a *data* message (silent) so the Flutter client can
invalidate/refetch the relevant Riverpod provider whether the app is
foregrounded or backgrounded. A visible `notification` payload is layered on
top only for events worth interrupting the user for (e.g. "segments ready
for review") — see call sites in workers/segmentation.py, workers/export.py,
and routers/consensus.py.

Uses Application Default Credentials — the same service account already
configured via GOOGLE_APPLICATION_CREDENTIALS for GCS/Cloud Run — so it needs
no separate secret, but that service account must have the "Firebase Cloud
Messaging API" enabled/permitted in the GCP project.

Never raises into the caller: a push failure should never fail a segmentation,
export, or retrain task. Errors are logged and swallowed.
"""
import uuid
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

_firebase_app = None


def _get_firebase_app():
    global _firebase_app
    if _firebase_app is None:
        import firebase_admin
        from firebase_admin import credentials
        _firebase_app = firebase_admin.initialize_app(credentials.ApplicationDefault())
    return _firebase_app


async def send_push_to_user(
    db: AsyncSession,
    user_id: uuid.UUID,
    data: dict[str, str],
    notification: dict[str, str] | None = None,
) -> None:
    """Push to every device registered for a single user."""
    await send_push_to_users(db, [user_id], data, notification)


async def send_push_to_users(
    db: AsyncSession,
    user_ids: list[uuid.UUID],
    data: dict[str, str],
    notification: dict[str, str] | None = None,
) -> None:
    if not user_ids:
        return

    from app.models.device_token import DeviceToken

    result = await db.execute(select(DeviceToken).where(DeviceToken.user_id.in_(user_ids)))
    tokens = result.scalars().all()
    if not tokens:
        return

    try:
        import firebase_admin
        from firebase_admin import messaging
        _get_firebase_app()

        stale_tokens: list[str] = []

        for dt in tokens:
            message = messaging.Message(
                token=dt.token,
                data=data,
                notification=(
                    messaging.Notification(
                        title=notification["title"], body=notification["body"]
                    )
                    if notification
                    else None
                ),
                android=messaging.AndroidConfig(priority="high"),
                apns=messaging.APNSConfig(
                    headers={"apns-priority": "10"},
                    payload=messaging.APNSPayload(aps=messaging.Aps(content_available=True)),
                ),
            )
            try:
                messaging.send(message)
            except (messaging.UnregisteredError, messaging.SenderIdMismatchError):
                stale_tokens.append(dt.token)
            except Exception as e:
                print(f"[push] Failed to send to token {dt.token[:12]}...: {e}")

        if stale_tokens:
            await db.execute(
                DeviceToken.__table__.delete().where(DeviceToken.token.in_(stale_tokens))
            )
            await db.commit()

    except Exception as e:
        # Firebase not configured, credentials missing, etc — never break the
        # calling task over a notification failure.
        print(f"[push] Push notification skipped due to error: {e}")
