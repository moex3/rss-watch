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
The key `lastElemName` can be defined to select the name of the field that will be used for last item detection. By default, this is `pubDate`.
The key `lastElemType` can be used to change the type of value in `lastElemName`. By default this is `timestring` which means it is a time string value, which will be parsed into a number.
The other possible value is `timeint` which is the same as `timestring` but it is already in a number, so no parsing happens.

Only new entries will be acted on. The file `~/.local/share/rss-watch/latest/FeedName` will store the last `guid` value from the feed.

Use cron, or other tools to run this script periodically.
