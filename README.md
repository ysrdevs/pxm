# pxm

Local PHP development for [Omarchy](https://omarchy.org), in the spirit of Laravel Herd.

Every folder in your sites folder becomes `https://<folder>.test`, with a trusted certificate and no
config files to write. Switch PHP and Node versions per project, run MySQL, PostgreSQL, Redis and Mailpit,
and give any site a public link to show someone. You can do it all from a bar icon, an app window or the
terminal.

## Features

- **Sites.** Every folder in your sites folder is served at `https://<folder>.test`. You can also link any
  other folder. HTTPS is on by default with a locally trusted certificate, and Laravel's `public/` folder is
  detected automatically.
- **PHP versions.** Quick prebuilt downloads take about a minute. Full builds with every extension (intl,
  sodium, …) compile in the background, including alphas, betas and RCs. Set a global version, or pin a
  project with `.php-version`. The `php` command and the web server both follow your choice.
- **Node versions.** pxm drives [mise](https://mise.jdx.dev), which Omarchy already ships. It sets the
  global version, pins projects with `.nvmrc`, and installs LTS lines.
- **Sharing.** Give a site a public `https://` link through Cloudflare Tunnel. Random
  `*.trycloudflare.com` links need no account. With your own Cloudflare domain, links look like
  `https://<site>.yourdomain.com` and stay the same every time. pxm warns you when debug mode is on, and it
  refuses to share phpMyAdmin.
- **Services.** MySQL, PostgreSQL, Redis and Mailpit run in Docker. Pick the ones you want during setup,
  or switch one on later and pxm downloads it then (about a minute, the first time only). The containers
  use the same names and settings as Omarchy's *Install > Development > Docker DB* menu, so containers made
  there are picked up too. The window shows the connection details and the `.env`
  lines for each service.
- **Mail.** Mailpit catches every email your apps send. The window shows the SMTP settings and can send a
  test email.
- **Logs.** See the latest Laravel and PHP errors for a site in one place.
- **Your apps.** Choose the editor, terminal, file manager and browser pxm opens. By default these follow
  Omarchy's own defaults.
- **Theme colours.** The bar icon and window use your Omarchy theme.

## Requirements

- Omarchy 4 (Arch Linux, Hyprland, systemd-resolved)
- Docker, if you want the database and mail services (Omarchy ships it)

`pxm setup` installs everything else from the Arch repos: `caddy`, `dnsmasq`, `nss`, `cloudflared`, `php`,
`php-fpm` and `composer`.

## Install

```bash
omarchy plugin add https://github.com/ysrdevs/pxm --enable
~/.config/omarchy/plugins/pxm/bin/pxm setup
```

The first command adds the bar icon and the window. The second does the one-time setup: it asks where
your sites folder should be and which services you want (MySQL, PostgreSQL, Redis, Mailpit, all or none),
asks for your password once, and downloads the latest PHP. If you'd rather use the bar, click the new icon
and choose **Set up pxm**.

Open a new terminal afterwards so `php` picks up pxm's version.

### What setup changes on your system

pxm only touches the files listed here, and `pxm uninstall` removes all of them.

| What | Where |
|---|---|
| Answers `*.test` with your own computer (dnsmasq on 127.0.0.2, used only for `.test`) | `/etc/pxm/dnsmasq.conf`, `pxm-dns.service`, `pxm-dns-route.service` in `/etc/systemd/system` |
| Keeps NetworkManager away from pxm's DNS link | `/etc/NetworkManager/conf.d/50-pxm-unmanaged.conf` |
| Lets the web server use ports 80 and 443 without running as root | `/etc/sysctl.d/50-pxm-web-ports.conf` |
| Trusts the local HTTPS certificate (made by Caddy on your computer) | `/etc/ca-certificates/trust-source/anchors/pxm-local-ca.crt`, `~/.pki/nssdb` |
| Web server and PHP-FPM, running as you | `~/.config/systemd/user/pxm-*` |
| The `php` command follows pxm | a marked block in `~/.bashrc` (and `~/.zshrc` if you have one) |
| The pxm window floats like an app window | a marked block in `~/.config/hypr/hyprland.lua` |
| The `pxm` command | `~/.local/bin/pxm` (a link into the plugin folder) |

PHP versions live in `~/.local/share/pxm` and settings in `~/.config/pxm`.

## Using it

Click the bar icon for quick switches. Click **Open pxm**, or run `pxm ui`, for the full window. Everything
in the window is also a command:

```bash
pxm sites                    # your sites and their PHP versions
pxm php install 8.4          # quick download
pxm php build 8.4            # full build with every extension, in the background
pxm php use 8.4              # global version
pxm php isolate 8.3          # pin this project (writes .php-version)
pxm node install lts
pxm node isolate 22          # pin this project (writes .nvmrc)
pxm link                     # serve the current folder as https://<folder>.test
pxm share                    # public link for the current site
pxm share domain example.com # use your own Cloudflare domain for share links
pxm service start mysql      # first start creates the container
pxm logs                     # latest errors for the current site
pxm doctor                   # check that everything is in place
pxm --help                   # everything else
```

### Connecting to the services

| Service | Address | Login |
|---|---|---|
| MySQL | `127.0.0.1:3306` | `root`, no password |
| PostgreSQL | `127.0.0.1:5432` | `postgres`, no password |
| Redis | `127.0.0.1:6379` | none |
| Mailpit SMTP | `127.0.0.1:1025` | none, inbox at http://localhost:8025 |

These are for local development only: every port listens on `127.0.0.1`, so other devices on your network
can't reach them.

Omarchy keeps your account out of Docker's admin group on purpose, so switching a service on or off asks
for your password. To skip that, turn on Omarchy's sudoless Docker option and restart.

## Uninstall

```bash
pxm uninstall            # keeps your PHP versions and settings, so setup can pick them up again
pxm uninstall --purge    # deletes those too
omarchy plugin remove pxm
```

Your sites and Docker databases are never touched. pxm also keeps the packages it installed, since other
apps may use them.

## How it works

- **Web server.** [Caddy](https://caddyserver.com) runs as your user. pxm writes its config from your sites
  folder, and a systemd path unit notices new folders straight away.
- **PHP.** Each PHP version runs its own PHP-FPM pool, and only for the versions your sites use. Quick
  versions are prebuilt by [static-php-cli](https://github.com/crazywhalecc/static-php-cli). Full builds are
  compiled on your computer with the same tool.
- **`*.test` addresses.** A small dnsmasq answers `*.test` with `127.0.0.1`. systemd-resolved sends it only
  `.test` lookups, so the rest of your DNS (including Omarchy's DNS over TLS) is unchanged.
- **Sharing.** Each shared site gets a private local port that tells PHP the request came in over https.
  That way Laravel builds correct links for the public address.
- **The bar icon and window.** These are an Omarchy shell plugin (`Panel.qml` and `Window.qml`). They read
  `pxm status --json` and run the same `pxm` commands you would type.

## Development

Clone the repo anywhere and link it in as the plugin:

```bash
git clone git@github.com:ysrdevs/pxm.git ~/Work/pxm
ln -s ~/Work/pxm ~/.config/omarchy/plugins/pxm
omarchy plugin enable pxm
~/Work/pxm/bin/pxm setup
```

After changing QML, run `omarchy restart shell`. The CLI is one Python file (`bin/pxm`, standard library
only).

## Credits

Made by [ysrdevs](https://github.com/ysrdevs). pxm isn't affiliated with Laravel or Laravel Herd. It builds
on Caddy, static-php-cli, mise, Cloudflare Tunnel, Mailpit and Omarchy.

## License

[MIT](LICENSE)
