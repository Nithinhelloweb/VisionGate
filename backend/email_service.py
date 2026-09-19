"""
Attenda Email Notification Service
Provides enterprise SMTP email capabilities with:
- Configurable SMTP server, port, credentials from DB (smtp_config table)
- Safe fallback when unconfigured (logs without crashing)
- Beautiful, professional HTML responsive templates conforming to Hallmark standards
- Specific notification handlers:
  * Leave Approved / Rejected
  * Attendance Correction Outcome
  * Daily HOD / Admin Pending Approvals Digest
  * Student Absence Warning Alert
  * Password Reset / Security Alert
"""

import os
import sys
import smtplib
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from datetime import datetime
from typing import Optional, Dict, Any, List

# Ensure backend directory is in sys.path
backend_dir = os.path.dirname(os.path.abspath(__file__))
if backend_dir not in sys.path:
    sys.path.insert(0, backend_dir)

import pg_adapter


def get_smtp_configuration() -> Dict[str, Any]:
    """Fetch active SMTP configuration from database."""
    try:
        cursor = pg_adapter.cursor
        cursor.execute("""
            SELECT host, port, username, password, sender_email, sender_name, use_tls, is_active
            FROM smtp_config
            WHERE id = 1
        """)
        row = cursor.fetchone()
        if not row:
            return {"is_active": False}
        return {
            "host": row[0] or "",
            "port": int(row[1] or 587),
            "username": row[2] or "",
            "password": row[3] or "",
            "sender_email": row[4] or "",
            "sender_name": row[5] or "Attenda Notification",
            "use_tls": bool(row[6]),
            "is_active": bool(row[7]),
        }
    except Exception as e:
        print(f"[EMAIL_SERVICE] Error loading SMTP config: {e}")
        return {"is_active": False}


def _get_base_email_template(title: str, preheader: str, body_html: str, action_url: Optional[str] = None, action_text: Optional[str] = None) -> str:
    """Standard responsive HTML email layout with Hallmark typography discipline (no italics in headings)."""
    action_button_html = ""
    if action_url and action_text:
        action_button_html = f"""
        <table role="presentation" border="0" cellpadding="0" cellspacing="0" style="margin: 28px 0;">
            <tr>
                <td align="center">
                    <a href="{action_url}" target="_blank" style="background-color: #1a56db; color: #ffffff; padding: 12px 24px; text-decoration: none; border-radius: 6px; font-size: 14px; font-weight: 600; display: inline-block;">{action_text}</a>
                </td>
            </tr>
        </table>
        """

    return f"""<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>{title}</title>
</head>
<body style="margin: 0; padding: 0; background-color: #f3f4f6; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; color: #1f2937;">
    <div style="display: none; max-height: 0; overflow: hidden; opacity: 0; font-size: 1px;">{preheader}</div>
    <table role="presentation" border="0" cellpadding="0" cellspacing="0" width="100%" style="background-color: #f3f4f6; padding: 32px 16px;">
        <tr>
            <td align="center">
                <table role="presentation" border="0" cellpadding="0" cellspacing="0" width="100%" style="max-width: 580px; background-color: #ffffff; border-radius: 8px; border: 1px solid #e5e7eb; overflow: hidden; box-shadow: 0 1px 3px rgba(0,0,0,0.05);">
                    <!-- Header -->
                    <tr>
                        <td style="background-color: #0f172a; padding: 24px 32px; border-bottom: 1px solid #1e293b;">
                            <div style="font-size: 20px; font-weight: 700; color: #ffffff; letter-spacing: -0.02em;">Attenda</div>
                            <div style="font-size: 12px; color: #94a3b8; margin-top: 4px;">Institutional Attendance &amp; Academic Management</div>
                        </td>
                    </tr>
                    <!-- Body Content -->
                    <tr>
                        <td style="padding: 32px;">
                            <h1 style="font-size: 18px; font-weight: 700; color: #0f172a; margin: 0 0 16px 0; font-style: normal; line-height: 1.4;">{title}</h1>
                            <div style="font-size: 14px; line-height: 1.6; color: #374151;">
                                {body_html}
                            </div>
                            {action_button_html}
                        </td>
                    </tr>
                    <!-- Footer -->
                    <tr>
                        <td style="background-color: #f8fafc; padding: 20px 32px; border-top: 1px solid #e2e8f0; font-size: 12px; color: #64748b; line-height: 1.5;">
                            This is an automated administrative notification sent from the Attenda system. For inquiries, contact your institution administrator.
                        </td>
                    </tr>
                </table>
            </td>
        </tr>
    </table>
</body>
</html>"""


def send_email(to_email: str, subject: str, body_html: str, preheader: str = "Attenda Notification", action_url: Optional[str] = None, action_text: Optional[str] = None) -> bool:
    """
    Send an email via configured SMTP.
    Returns True if sent successfully, False if unconfigured or failed.
    """
    if not to_email or "@" not in to_email:
        print(f"[EMAIL_SERVICE] Invalid recipient email: '{to_email}'")
        return False

    config = get_smtp_configuration()
    if not config.get("is_active") or not config.get("host") or not config.get("username"):
        print(f"[EMAIL_SERVICE] SMTP is unconfigured or inactive. Notification to '{to_email}' logged but not dispatched.")
        return False

    full_html = _get_base_email_template(
        title=subject,
        preheader=preheader,
        body_html=body_html,
        action_url=action_url,
        action_text=action_text
    )

    msg = MIMEMultipart("alternative")
    msg["Subject"] = subject
    msg["From"] = f"{config['sender_name']} <{config['sender_email'] or config['username']}>"
    msg["To"] = to_email

    # Plain text version as fallback
    text_content = f"{subject}\n\n" + body_html.replace("<br>", "\n").replace("<p>", "\n").replace("</p>", "\n")
    msg.attach(MIMEText(text_content, "plain", "utf-8"))
    msg.attach(MIMEText(full_html, "html", "utf-8"))

    try:
        server = smtplib.SMTP(config["host"], config["port"], timeout=10)
        if config["use_tls"]:
            server.starttls()
        if config["password"]:
            server.login(config["username"], config["password"])
        server.sendmail(config["sender_email"] or config["username"], [to_email], msg.as_string())
        server.quit()
        print(f"[EMAIL_SERVICE] Email successfully sent to '{to_email}' — Subject: {subject}")
        return True
    except Exception as e:
        print(f"[EMAIL_SERVICE] Failed to send email to '{to_email}': {e}")
        return False


def notify_leave_status_change(recipient_email: str, staff_name: str, leave_type: str, start_date: str, end_date: str, status: str, remarks: Optional[str] = None) -> bool:
    """Send leave status update email (Approved / Rejected)."""
    status_color = "#059669" if status.lower() == "approved" else "#dc2626"
    body_html = f"""
    <p>Dear <strong>{staff_name}</strong>,</p>
    <p>Your request for <strong>{leave_type}</strong> covering <strong>{start_date}</strong> to <strong>{end_date}</strong> has been updated to:</p>
    <div style="display: inline-block; padding: 6px 14px; border-radius: 4px; background-color: {status_color}; color: #ffffff; font-weight: 700; font-size: 13px; margin: 8px 0 16px 0;">
        {status.upper()}
    </div>
    {f'<p style="background-color: #f1f5f9; padding: 12px; border-left: 4px solid #94a3b8; border-radius: 4px;"><strong>Reviewer Remarks:</strong> {remarks}</p>' if remarks else ''}
    <p>You can verify your leave balances and attendance logs directly in the Attenda portal.</p>
    """
    subject = f"Leave Request {status.capitalize()} — {leave_type}"
    return send_email(to_email=recipient_email, subject=subject, body_html=body_html, preheader=f"Your {leave_type} request was {status.lower()}")


def notify_attendance_correction_outcome(recipient_email: str, staff_name: str, requested_date: str, requested_status: str, outcome_status: str, remarks: Optional[str] = None) -> bool:
    """Send attendance correction outcome email."""
    status_color = "#059669" if outcome_status.lower() == "approved" else "#dc2626"
    body_html = f"""
    <p>Dear <strong>{staff_name}</strong>,</p>
    <p>Your attendance correction dispute for <strong>{requested_date}</strong> (Requested status: <strong>{requested_status}</strong>) has been processed:</p>
    <div style="display: inline-block; padding: 6px 14px; border-radius: 4px; background-color: {status_color}; color: #ffffff; font-weight: 700; font-size: 13px; margin: 8px 0 16px 0;">
        {outcome_status.upper()}
    </div>
    {f'<p style="background-color: #f1f5f9; padding: 12px; border-left: 4px solid #94a3b8; border-radius: 4px;"><strong>Review Notes:</strong> {remarks}</p>' if remarks else ''}
    <p>Your official attendance register reflects this decision.</p>
    """
    subject = f"Attendance Correction {outcome_status.capitalize()} — {requested_date}"
    return send_email(to_email=recipient_email, subject=subject, body_html=body_html, preheader=f"Attendance correction outcome for {requested_date}")


def notify_daily_pending_digest(hod_email: str, hod_name: str, dept: str, pending_leaves: int, pending_corrections: int) -> bool:
    """Send daily pending actions digest to HOD or Admin."""
    total_actions = pending_leaves + pending_corrections
    if total_actions == 0:
        return False

    body_html = f"""
    <p>Dear <strong>{hod_name}</strong>,</p>
    <p>You have <strong>{total_actions} pending request(s)</strong> awaiting your administrative review for Department <strong>{dept}</strong>:</p>
    <table role="presentation" border="0" cellpadding="8" cellspacing="0" style="width: 100%; border-collapse: collapse; margin: 16px 0; border: 1px solid #e2e8f0;">
        <tr style="background-color: #f8fafc; border-bottom: 1px solid #e2e8f0;">
            <th align="left" style="font-size: 13px; color: #475569;">Request Category</th>
            <th align="right" style="font-size: 13px; color: #475569;">Pending Count</th>
        </tr>
        <tr style="border-bottom: 1px solid #e2e8f0;">
            <td style="font-size: 13px;">Leave / OD Requests</td>
            <td align="right" style="font-size: 13px; font-weight: 700;">{pending_leaves}</td>
        </tr>
        <tr>
            <td style="font-size: 13px;">Attendance Dispute Corrections</td>
            <td align="right" style="font-size: 13px; font-weight: 700;">{pending_corrections}</td>
        </tr>
    </table>
    <p>Please log in to your Attenda portal to review and clear these items.</p>
    """
    subject = f"Daily Action Digest — {total_actions} Pending Approvals ({dept})"
    return send_email(to_email=hod_email, subject=subject, body_html=body_html, preheader=f"You have {total_actions} pending items to review today")


# ─────────────────────────────────────────────────────────────────────────────
# STAFF LEAVE ALTERNATE-ASSIGNMENT NOTIFICATIONS
# ─────────────────────────────────────────────────────────────────────────────

def notify_alternate_nomination(
    email: str,
    alternate_name: str,
    requester_name: str,
    requester_dept: str,
    leave_type: str,
    start_date: str,
    end_date: str,
    request_id: int,
) -> bool:
    """Notify the nominated alternate that they have been asked to cover timetable slots."""
    body_html = f"""
    <p>Dear <strong>{alternate_name}</strong>,</p>
    <p>
        <strong>{requester_name}</strong> ({requester_dept}) has nominated you as their
        alternate staff member for the following leave request:
    </p>
    <table role="presentation" border="0" cellpadding="8" cellspacing="0"
           style="width:100%;border-collapse:collapse;margin:16px 0;border:1px solid #e2e8f0;">
        <tr style="background-color:#f8fafc;border-bottom:1px solid #e2e8f0;">
            <td style="font-size:13px;color:#475569;font-weight:600;">Leave type</td>
            <td style="font-size:13px;">{leave_type.upper()}</td>
        </tr>
        <tr style="border-bottom:1px solid #e2e8f0;">
            <td style="font-size:13px;color:#475569;font-weight:600;">Period</td>
            <td style="font-size:13px;">{start_date} &ndash; {end_date}</td>
        </tr>
        <tr style="background-color:#f8fafc;">
            <td style="font-size:13px;color:#475569;font-weight:600;">Request ID</td>
            <td style="font-size:13px;">#{request_id}</td>
        </tr>
    </table>
    <div style="background-color:#fef3c7;border-left:4px solid #f59e0b;
                padding:12px 16px;border-radius:4px;margin:16px 0;">
        <strong>Response required within 24 hours.</strong> Log in to Attenda to accept
        or decline. If you do not respond, the nomination expires automatically.
    </div>
    <p>
        Accepting this request will record your timetable coverage for the leave period.
        Declining will require the requester to nominate a different alternate.
    </p>
    """
    subject = f"Coverage request — {requester_name} ({leave_type.upper()}, {start_date} to {end_date})"
    return send_email(
        to_email=email,
        subject=subject,
        body_html=body_html,
        preheader=f"{requester_name} has nominated you as alternate. Respond within 24 hours.",
    )


def notify_alternate_accepted(
    hod_email: Optional[str],
    admin_email: Optional[str],
    requester_name: str,
    requester_dept: str,
    alternate_name: str,
    leave_type: str,
    start_date: str,
    end_date: str,
    request_id: int,
) -> bool:
    """
    Email HOD and Admin once the alternate confirms coverage.
    Sent individually so either address being None does not silence the other.
    """
    body_html = f"""
    <p>
        <strong>{requester_name}</strong> ({requester_dept}) has filed a leave request.
        The nominated alternate <strong>{alternate_name}</strong> has
        <span style="color:#059669;font-weight:700;">confirmed coverage</span>,
        and timetable handover slots have been recorded.
    </p>
    <table role="presentation" border="0" cellpadding="8" cellspacing="0"
           style="width:100%;border-collapse:collapse;margin:16px 0;border:1px solid #e2e8f0;">
        <tr style="background-color:#f8fafc;border-bottom:1px solid #e2e8f0;">
            <td style="font-size:13px;color:#475569;font-weight:600;">Requester</td>
            <td style="font-size:13px;">{requester_name} &mdash; {requester_dept}</td>
        </tr>
        <tr style="border-bottom:1px solid #e2e8f0;">
            <td style="font-size:13px;color:#475569;font-weight:600;">Leave type</td>
            <td style="font-size:13px;">{leave_type.upper()}</td>
        </tr>
        <tr style="background-color:#f8fafc;border-bottom:1px solid #e2e8f0;">
            <td style="font-size:13px;color:#475569;font-weight:600;">Period</td>
            <td style="font-size:13px;">{start_date} &ndash; {end_date}</td>
        </tr>
        <tr style="border-bottom:1px solid #e2e8f0;">
            <td style="font-size:13px;color:#475569;font-weight:600;">Alternate confirmed</td>
            <td style="font-size:13px;">{alternate_name}</td>
        </tr>
        <tr style="background-color:#f8fafc;">
            <td style="font-size:13px;color:#475569;font-weight:600;">Request ID</td>
            <td style="font-size:13px;">#{request_id}</td>
        </tr>
    </table>
    <p>Log in to the Attenda portal to review the timetable coverage and approve or reject this request.</p>
    """
    subject = f"Staff leave — coverage confirmed, approval required [{requester_name}]"
    preheader = f"{requester_name} leave: {alternate_name} confirmed. Your approval needed."
    sent = False
    if hod_email:
        sent = send_email(to_email=hod_email, subject=subject, body_html=body_html, preheader=preheader) or sent
    if admin_email:
        sent = send_email(to_email=admin_email, subject=subject, body_html=body_html, preheader=preheader) or sent
    return sent


def notify_requester_final_outcome(
    requester_email: str,
    name: str,
    leave_type: str,
    status: str,
    start_date: str,
    end_date: str,
    remarks: Optional[str] = None,
) -> bool:
    """Notify the leave requester of the Admin's final decision."""
    is_approved = status.lower() in ("approved", "approve")
    status_color = "#059669" if is_approved else "#dc2626"
    status_label = "APPROVED" if is_approved else "REJECTED"

    body_html = f"""
    <p>Dear <strong>{name}</strong>,</p>
    <p>
        Your <strong>{leave_type.upper()}</strong> leave request covering
        <strong>{start_date}</strong> to <strong>{end_date}</strong>
        has been reviewed. The final decision is:
    </p>
    <div style="display:inline-block;padding:8px 18px;border-radius:4px;
                background-color:{status_color};color:#ffffff;
                font-weight:700;font-size:14px;margin:12px 0 20px 0;">
        {status_label}
    </div>
    {f'<p style="background-color:#f1f5f9;padding:12px 16px;border-left:4px solid #94a3b8;border-radius:4px;"><strong>Reviewer remarks:</strong> {remarks}</p>' if remarks else ''}
    {'<p>Your attendance record has been updated to reflect the approved leave.</p>' if is_approved else '<p>No changes have been made to your attendance record. Contact your HOD or Admin if you have questions.</p>'}
    """
    subject = f"Leave request {status_label.lower()} — {leave_type.upper()} ({start_date} to {end_date})"
    return send_email(
        to_email=requester_email,
        subject=subject,
        body_html=body_html,
        preheader=f"Your {leave_type} leave request was {status.lower()}.",
    )
