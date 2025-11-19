# Autolink Tests

## URL Autolinks

<https://example.com>

<http://www.example.org>

<https://example.com/path/to/page>

<https://example.com/path?query=param&other=value>

## Email Autolinks

<user@example.com>

<john.doe@example.org>

<contact+tag@example.com>

## Plain URLs (may or may not auto-link depending on parser)

Visit https://example.com for more.

Check out http://www.example.org too.

## Mixed Content

Email me at <user@example.com> or visit <https://example.com>.

## Edge Cases

Multiple autolinks: <https://first.com> and <https://second.com>.

Autolink at start: <https://start.com>

End with autolink: <https://end.com>

## In Lists

- <https://example.com>
- <user@example.com>
- Regular text
