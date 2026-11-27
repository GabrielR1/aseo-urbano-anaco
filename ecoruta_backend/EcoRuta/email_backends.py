import json
import logging
import urllib.error
import urllib.request

from django.conf import settings
from django.core.mail.backends.base import BaseEmailBackend

logger = logging.getLogger(__name__)


class WebhookEmailBackend(BaseEmailBackend):
    """
    Envía correos vía HTTPS (puerto 443) a un webhook (por ejemplo un Google Apps Script
    vinculado a la cuenta Gmail institucional). Evita el bloqueo de puertos SMTP 25/465/587
    en planes gratuitos como Render Free.
    """

    def send_messages(self, email_messages):
        url = (getattr(settings, 'EMAIL_WEBHOOK_URL', '') or '').strip()
        secret = (getattr(settings, 'EMAIL_WEBHOOK_SECRET', '') or '').strip()
        timeout = getattr(settings, 'EMAIL_TIMEOUT', 15)
        if not url or not email_messages:
            return 0

        sent_count = 0
        for message in email_messages:
            recipients = list(message.to or [])
            if not recipients:
                continue

            html_body = ''
            for alt_content, mimetype in getattr(message, 'alternatives', []) or []:
                if mimetype == 'text/html':
                    html_body = alt_content
                    break

            payload = {
                'secret': secret,
                'to': ','.join(recipients),
                'subject': message.subject or '',
                'body': message.body or '',
                'htmlBody': html_body,
                'fromName': getattr(settings, 'EMAIL_SENDER_NAME', 'Aseo Urbano Anaco'),
            }
            data = json.dumps(payload).encode('utf-8')
            req = urllib.request.Request(
                url,
                data=data,
                headers={'Content-Type': 'application/json; charset=utf-8'},
                method='POST',
            )
            try:
                with urllib.request.urlopen(req, timeout=timeout) as resp:
                    raw = resp.read().decode('utf-8', errors='replace')
                    if resp.status >= 400:
                        raise RuntimeError(f'Webhook HTTP {resp.status}: {raw[:200]}')
                    try:
                        parsed = json.loads(raw)
                        if isinstance(parsed, dict) and parsed.get('ok') is False:
                            raise RuntimeError(parsed.get('error') or 'Error en webhook de correo')
                    except ValueError:
                        pass
                    sent_count += 1
            except Exception:
                logger.exception('Error enviando correo vía webhook HTTPS a %s', recipients)
                if not self.fail_silently:
                    raise
        return sent_count
