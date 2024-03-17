# rss-watch.pl

Perl script to monitor RSS feeds and execute scripts.

## config

The config file is stored in `~/.config/rss-watch/config`. Example configuration file:
```cfg
[feed FeedName]
url = https://rss.example.com/
script = /home/user/script_to_exec.sh '$title' '$link' '$guid<isPermaLink>'
```

This will query the url specified by the `url` key for an RSS feed and execute the given script with the arguments `title` and `link` from the feed.
Attributes can be selected by enclosing the attribue key in `<>` characters. For example, to select the `isPermaLink` attribute of the `guid` key, the selector would be `$guid<isPermaLink>`.
Multiple script keys can be specified on new lines, which will all be executed.

Only new entries will be acted on. The file `~/.local/share/rss-watch/latest/FeedName` will store the last `guid` value from the feed.

Use cron, or other tools to run this script periodically.
