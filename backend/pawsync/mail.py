import smtplib
import ssl
from email.message import EmailMessage

from .wallet import WalletError


def send_restore_code(settings, email, code):
    if not settings.smtp_host:
        raise WalletError("Purchase restoration email is not configured", 503)
    message = EmailMessage()
    message["From"] = settings.mail_from
    message["To"] = email
    message["Subject"] = "Your PawSync purchase restoration code"
    message.set_content(f"Your one-time PawSync code is {code}.\n\nIt expires in 10 minutes. If you did not request this code, ignore this email.\n")
    with smtplib.SMTP(settings.smtp_host, settings.smtp_port, timeout=5) as server:
        server.starttls(context=ssl.create_default_context())
        if settings.smtp_username:
            server.login(settings.smtp_username, settings.smtp_password)
        server.send_message(message)
