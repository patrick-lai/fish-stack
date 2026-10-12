# Shared tray

One menu-bar item serves every app. Fish Stack owns it whenever Fish Stack is running. Other apps add a tab to it. When Fish Stack is not running, each app keeps its own tray.

## Owner

- Fish Stack is the owner whenever it is running. It creates the one menu-bar item and shows a tab for each live guest.
- Fish Stack's own tab is always last.
- With no guests, the popover shows Fish Stack's panel alone, with no tab bar.

## Registering a tab (guest apps)

While it runs, a guest app writes one file, `<home>/tray/<id>.json`, where `<home>` is `$FISH_STACK_HOME` or `~/.fishStack`:

```json
{
  "id": "commissionai",
  "title": "CommissionAI",
  "order": 10,
  "url": "http://127.0.0.1:7433/tray",
  "pid": 12345
}
```

- `id`: 1 to 40 characters from `a-z`, `0-9` and `-`. `fishstack` is reserved.
- `title`: the tab label.
- `order`: lower comes first. Fish Stack's tab is always last.
- `url`: a loopback `http` page. The popover loads it in a web view. Guests put a random token in the path, so only processes that read this file can reach the page.
- `pid`: the guest's process id. Fish Stack drops the tab once that process has exited.

Write the file atomically (temporary file, then rename). Delete it on exit. Fish Stack watches the folder and each guest's process, so it reacts as soon as either changes. Nothing is polled.

## Owner record

While the Fish Stack app runs, it writes `<home>/tray/owner.json` with its process id, and removes the file when it quits:

```json
{ "pid": 4321 }
```

## Falling back

A guest checks `<home>/tray/owner.json`. If the file names a live process, Fish Stack owns the tray: the guest registers its tab and removes its own menu-bar item. Otherwise the guest keeps its own tray, as it does today.

Fish Stack picks up a guest as soon as it registers, and drops the tab as soon as the guest's process exits. A guest page is loaded each time the popover opens. The popover takes the height of the page's `body`: Fish Stack injects a script that posts it through the `fishStackHeight` message handler whenever it changes.
