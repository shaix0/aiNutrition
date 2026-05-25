# app/notifications.py

from fastapi import APIRouter, Form, HTTPException
from fastapi.responses import HTMLResponse
import firebase_admin
from firebase_admin import credentials, messaging
from pydantic import BaseModel

router = APIRouter()

class NotificationRequest(BaseModel):
    title: str
    body: str


@router.post("/send")
async def send_notification(data: NotificationRequest):
    message = messaging.Message(
        data={
            "title": data.title,
            "body": data.body,
        },
        topic="all",
        # token="frEu2SI3lwFOFlRh7xOOAP:APA91bEYSuocjcBWe9D3qOzZ9C9x4RTy_IXcu6I11XOCy6UDCz7z0_lhm1zz25ewB_qddFLy74s0gVbPU3OTb4RKPssHAqs5pkGjEBKZw2h6uLTO4yuEehA"
    )

    response = messaging.send(message)

    return {"status": "success", "message_id": response}

@router.post("/sendtotarget")
async def send_notification_to_target(target_uid: str = Form(...), title: str = Form(...), body: str = Form(...)):
    tokens = await get_user_fcm_tokens(target_uid)
    tokens = list(set(tokens))  # 去除重複 token
    for token in tokens:
        message = messaging.Message(
            title=title,
            body=body,
            # data={
            #     "title": title,
            #     "body": body,
            # },
            token=token,
        )
        response = messaging.send(message)
        return {"status": "success", "message_ids": response}

async def get_user_fcm_tokens(user_id: str) -> list[str]:
    from firebase_admin import firestore
    db = firestore.client()
    
    tokens_ref = db.collection("users").document(user_id).collection("tokens")
    token_docs = tokens_ref.stream()
    
    tokens = [doc.to_dict().get("token") for doc in token_docs]
    tokens = [t for t in tokens if t]  # 過濾空值
    
    if not tokens:
        raise HTTPException(status_code=404, detail="User not found or no tokens available")
    
    return tokens