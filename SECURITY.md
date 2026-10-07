# Security

Buddy runs on your Mac and sends nothing anywhere by itself. The parts worth a careful look are the hook (`beat.py`, which reads your agents' session logs), the optional Claude plan limits (which read a Keychain item), and `install.sh`.

**Found a problem?** Please report it privately: open the repo's **Security** tab → **Report a vulnerability**. Don't open a public issue. You'll get a reply within a week.
