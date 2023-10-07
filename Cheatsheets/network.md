# Network  Cheatsheet


## curl


| Command | Description |
|--|--|
| `curl -v [URL] --resolve [URL]:[PORT]:[TARGET IP]` | Resolve domain name with specific IP<br />Example: curl -v https://google.com --resolve google.com:443:192.168.0.1|