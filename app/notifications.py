# app/notifications.py

from fastapi import APIRouter, Form, HTTPException
from fastapi.responses import HTMLResponse
import firebase_admin
from firebase_admin import credentials, messaging

router = APIRouter()

# =========================
# 📄 後台頁面（表單）
# =========================
@router.get("/", response_class=HTMLResponse)
async def notification_page():
    return """
    <html>
        <head>
            <title>通知後台</title>
        </head>
        <body>
            <h2>發送通知</h2>
            <form action="/notifications/send" method="post">
                <label>標題：</label><br>
                <input type="text" name="title" required><br><br>

                <label>內容：</label><br>
                <textarea name="body" required></textarea><br><br>

                <button type="submit">發送</button>
            </form>
        </body>
    </html>
    """


# =========================
# 🚀 發送通知
# =========================
@router.post("/send")
async def send_notification(
    title: str = Form(...),
    body: str = Form(...)
):
    if not title or not body:
        raise HTTPException(status_code=400, detail="標題或內容不能為空")

    try:
        message = messaging.Message(
            data={
                "title": title,
                "body": body,
            },
            topic="all"  # ⭐ 發給所有訂閱者
        )

        response = messaging.send(message)

        return {
            "status": "success",
            "message_id": response
        }

    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))