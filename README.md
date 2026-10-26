# Privatus Analytics for Haskell

**Real visitor numbers for your Haskell web app. No cookies, no cookie pop-up, no bots.**

You want to know if people use your Haskell web app. But Google Analytics uses
cookies, so in many countries you must show a cookie pop-up first (the box that
asks visitors to say yes to cookies). Many people click no, so they never show
up in your numbers. Bots add fake visits on top.

This package adds the Privatus Analytics script to your Haskell web app. Print
the tag with a helper for lucid or blaze-html, or let a WAI middleware put it in
the page head for you. WAI is the shared base that Yesod, Servant, Scotty and
most other Haskell web servers use. The script sets no cookies and keeps no IP
addresses. Bots are filtered out before they are counted.

So you see how many real people came, which pages they looked at and where they
came from, on one simple dashboard. A report comes to your inbox each week, and
you can set alerts for when traffic jumps or drops. And you don't need a cookie
pop-up for your analytics.

**Free plan, no card:** 10,000 events a month (an event is a page view or an action you track) on up to 3 sites. [Start free at privatusanalytics.com](https://privatusanalytics.com).

- **No cookies.** No cookies and no hidden IDs on your visitors' devices, and no IP
  addresses are kept. Laws differ by country, so check your own legal advice.
- **Real people, not bots.** Known bots, data centers and spam visits are left
  out on every plan.
- **Small and fast.** The script is about 3 KB when compressed.

The package only prints the browser script. It never sends events from your
server and sets no cookies. You need a Privatus Analytics account to see
reports, and there is a free plan. Sign up at https://privatusanalytics.com.

## Requirements

* GHC 9.6 or later, with cabal or stack.
* A Privatus Analytics site id (it starts with `pa_`). You find it under
  Site settings, Tracking.

## Install

Add the package to `build-depends` in your `.cabal` file:

```cabal
build-depends: privatus-analytics ^>=1.0
```

Then run `cabal build`. For the full setup guide and every tracker option,
see the [Privatus Analytics docs](https://privatusanalytics.com/docs).

Set your site id with an environment variable, and tell the package that it
runs in production:

```sh
PRIVATUS_SITE_ID=pa_YOURSITEID
PRIVATUS_ENV=production   # or APP_ENV=production
```

Then load the settings once when your app starts:

```haskell
import PrivatusAnalytics

main :: IO ()
main = do
  config <- loadConfig
  ...
```

Or set the site id in code:

```haskell
config <- fromEnvironment defaultConfig {configSiteId = Just "pa_YOURSITEID"}
```

## Add the tag

Put the tag in the `<head>` of your layout. With
[lucid](https://hackage.haskell.org/package/lucid):

```haskell
import PrivatusAnalytics
import PrivatusAnalytics.Lucid

layout :: Config -> Html () -> Html ()
layout config content = html_ $ do
  head_ $ do
    title_ "My app"
    analyticsTag_ config defaultTagOptions
  body_ content
```

With [blaze-html](https://hackage.haskell.org/package/blaze-html):

```haskell
import PrivatusAnalytics
import PrivatusAnalytics.Blaze

H.head $ do
  H.title "My app"
  analyticsTagHtml config defaultTagOptions
```

With anything else, `analyticsTag config defaultTagOptions` gives `Text` and
`analyticsTagBS` gives UTF-8 bytes. In production it prints:

```html
<script defer src="https://privatusstats.com/js/pa.js" data-site="pa_YOURSITEID"></script>
```

The tag prints nothing when there is no site id, and nothing outside
production (see below). The one exception is the queue stub: when it is on,
it still prints (see [Track from your own JavaScript](#track-from-your-own-javascript)). If your app uses a Content Security Policy nonce, pass
it in: `defaultTagOptions {tagNonce = Just nonce}`. A Content Security Policy
is a header that tells the browser which scripts may run, and a nonce is the
one-time code that lets an inline script through.

### Or let the middleware add it

If you would rather not touch your layouts, wrap your app with the WAI
middleware:

```haskell
import Network.Wai.Handler.Warp (run)
import PrivatusAnalytics
import PrivatusAnalytics.Wai (privatusMiddleware)

main :: IO ()
main = do
  config <- loadConfig
  run 3000 (privatusMiddleware config app)
```

It adds the tag just before `</head>` in uncompressed `text/html` responses with
status 200, and fixes the `Content-Length` header. It skips Ajax requests,
pages without a `<head>`, and pages that already have the tag. Responses that
have a `Content-Encoding` header are left alone, so if you compress with
`Network.Wai.Middleware.Gzip`, put `privatusMiddleware` inside it:
`gzip def (privatusMiddleware config app)`. For the nonce, the middleware uses
`configNonceFor` if you set it, or else reads the `'nonce-...'` value from the
response's `Content-Security-Policy` header.

## Configuration

Every setting is optional except the site id. `Config` is a plain record, so
you change it with record update syntax:

```haskell
config <- loadConfig
let privatus =
      config
        { configSiteId = Just "pa_YOURSITEID",       -- or PRIVATUS_SITE_ID
          configScriptHost = Just "https://privatusstats.com", -- or PRIVATUS_SCRIPT_HOST
          configModules = Just ["engage", "auto", "vitals", "clicks", "ask"],
          configExcludedPaths = ["/admin/*", "/preview/*"],
          configDomains = ["example.com", "www.example.com"],
          configSpa = Just SpaAuto,                  -- SpaAuto, SpaHistory, SpaHash or SpaOff
          configManual = False,                      -- True turns off the automatic pageview
          configEnabledEnvironments = ["production"],
          configExtraAttributes = [("data-mask", "/orders/*->/orders/:id")],
          configProps = [("app_version", "2.4")],
          configRequestProps = Just (\request -> pure [("section", "app")]),
          configQueueStub = False
        }
```

| Setting | Default | What it does |
|---|---|---|
| `configSiteId` | `PRIVATUS_SITE_ID` | The `data-site` attribute. Nothing prints without it |
| `configScriptHost` | `https://privatusstats.com` | Where `/js/pa.js` is served. Change it only if you host your own copy. Also read from `PRIVATUS_SCRIPT_HOST` |
| `configModules` | tracker default (`engage`) | The `data-modules` attribute. Setting it replaces the default, so keep `engage` for time on page and scroll depth. `Just []` loads none |
| `configExcludedPaths` | none | The `data-exclude` attribute. Path globs the tracker never counts |
| `configDomains` | all hosts | The `data-domains` attribute. Count only these hostnames |
| `configSpa` | `Nothing` (auto) | The `data-spa` attribute |
| `configManual` | `False` | The `data-manual` attribute |
| `configEnvironment` | `PRIVATUS_ENV`, else `APP_ENV` | The environment your app runs in |
| `configEnabledEnvironments` | `["production"]` | Environments that get the tag |
| `configEnabled` | `Nothing` | `Just True` or `Just False` forces the tag on or off in every environment |
| `configExtraAttributes` | `[]` | Any other `data-*` attribute |
| `configProps` | `[]` | Page props sent with every pageview and event. See below |
| `configRequestProps` | `Nothing` | A function that gets the WAI request and gives more page props. See below |
| `configQueueStub` | `False` | Prints a small script first, so `privatus.track` calls made before the tracker loads are kept and sent later. It still prints when the tag is off, so those calls never fail |
| `configNonceFor` | `const Nothing` | Gives the middleware the nonce for a request |

To add the tag, you call a helper or use `privatusMiddleware`. There is no
separate "auto inject" switch: wrapping your app with the middleware is the
switch.

Each tracker attribute is explained in the [script attributes
reference](https://privatusanalytics.com/docs/tracker/attributes), and the
modules in [Modules](https://privatusanalytics.com/docs/tracker/modules).

You can also change a setting for one page:

```haskell
analyticsTag_ config {configModules = Just ["engage", "auto"], configExcludedPaths = ["/preview/*"]} defaultTagOptions
```

### Development and test

Development, test and staging runs are not counted by default, so your own
clicking around never reaches your reports. The tag prints only when
`PRIVATUS_ENV` (or `APP_ENV`) is `production`. To see the tag while you build,
set `configEnabled = Just True`. The tracker also ignores `localhost` unless
you pass `data-allow-local` or `data-debug` (see [Debug
mode](https://privatusanalytics.com/docs/tracker/debug)):

```haskell
config {configExtraAttributes = [("data-debug", "true")]}
```

### Leaving people out

Use `data-exclude` through `configExcludedPaths` for admin areas. To leave out
signed-in staff, print the tag only for other people:

```haskell
unless (isAdmin user) (analyticsTag_ config defaultTagOptions)
```

## Product analytics: see which features people use

Privatus can show which buttons, forms and features people really use. You
add a few attributes to your HTML. The tracker reads them in the browser and
sends the events. Your server still sends nothing.

### Props

A prop is a key and a value. With `OverloadedStrings`, a text prop is just a
pair of strings. For other values use `=:` (or `prop`):

```haskell
[("format", "csv"), "seats" =: (5 :: Int), "beta" =: True, "flags" =: ["a", "b" :: Text]]
```

`Nothing` and `PropNull` leave a prop out.

### Name events well

Use a short "Noun verb" name, like `Report exported` or `Invite sent`. Put the
details in props, not in the name. So write `Report exported` with
`("format", "csv")`, not `Report exported as CSV`. Then all exports add up in
one place, and you can split them by format.

### Events on buttons, links and forms

With lucid, `eventAttrs_` gives a list of attributes:

```haskell
button_ ([class_ "btn"] <> eventAttrs_ "Report exported" [("format", "csv"), ("source", "toolbar")]) "Export"
```

It prints:

```html
<button class="btn" data-privatus-event="Report exported" data-privatus-prop-format="csv" data-privatus-prop-source="toolbar">Export</button>
```

With blaze-html, `eventAttribute` works with `!`:

```haskell
H.button ! eventAttribute "Report exported" [("format", "csv")] $ "Export"
```

With any other template, `eventAttrs` gives escaped HTML text to put inside a
tag, and `eventData` gives the plain name and value pairs.

On a form, the event is sent when the form is submitted:

```haskell
form_ ([action_ "/newsletter", method_ "post"] <> eventAttrs_ "Newsletter joined" [("list", "weekly")]) $ do
  ...
```

The rules:

* The name is trimmed and cut to 120 characters. An empty name prints nothing.
* Prop keys are made lowercase. Anything that is not a letter, a digit or `_`
  becomes `_`, so `"Report Type"` becomes `report_type`. Keys are cut to 64
  characters.
* At most 30 props. Values become text: `true`, `false`, numbers as written,
  lists joined with commas. Null values are left out. Values are cut to 500
  characters.
* Everything is escaped for HTML.
* The attributes print in every environment, even when the tag is off. They do
  nothing without the tracker, so your pages look the same in development and
  production.

### Click maps

A click map shows where people click on a page. Give the important parts a
name so they stay easy to find, even when the page changes:

```haskell
a_ (href_ "/pricing" : clickAttr_ "pricing.cta") "See plans"         -- lucid
H.a ! A.href "/pricing" ! clickAttribute "pricing.cta" $ "See plans" -- blaze-html
```

A name may use letters, digits and `_ . : -`, up to 100 characters. Anything
else prints nothing. `validClickName` tells you if a name is valid, so you can
check your names in a test.

### Page props: plan, role and other groups

Page props are sent with every pageview and event on the page. Use them to
split your reports by plan, role, app version, feature flag or account tier.

Set the same props for every page with `configProps`. For props that depend
on the request, set `configRequestProps`. It gets the WAI request and runs in
`IO`, so it can look things up:

```haskell
config
  { configProps = [("app_version", "2.4")],
    configRequestProps = Just $ \request -> do
      account <- currentAccount request
      pure ["plan" =: accountPlan account, "role" =: accountRole account]
  }
```

The middleware runs it for each page. In a handler, use
`analyticsTagFor config options request` to get the tag with it. It only runs
when the tag prints.

You can also set or change props for one page. They are merged over the
configured ones, and `PropNull` removes one:

```haskell
analyticsTag_ config defaultTagOptions {tagProps = [("section", "billing"), ("role", PropNull)]}
```

The tag then prints a small script before the tracker, with your Content
Security Policy nonce when you have one, and points the tracker at it:

```html
<script nonce="...">window.privatusPageProps=function(){return {"plan":"pro","role":"admin"}}</script>
<script defer src="https://privatusstats.com/js/pa.js" data-site="pa_YOURSITEID" data-props="privatusPageProps"></script>
```

Keys follow the same rules as event props. Numbers and `True` or `False` stay
as they are, and lists stay lists (up to 30 items). The props are escaped so
they are safe inside a script. `pagePropsJson` gives you the JSON on its own.

**Never put names, emails, user ids or anything that points to one person in
props.** Privatus counts visitors without any id. Put groups (like the plan or
the role), not people. The server also removes emails and long ids it finds.

### Track from your own JavaScript

For things that are not a click or a submit, call the tracker from your
JavaScript, as the [JavaScript API
docs](https://privatusanalytics.com/docs/tracker/javascript-api) explain:

```js
privatus.track("Feature used", { feature: "export" })
```

If your code may run before the tracker has loaded, switch on the queue stub.
It prints a tiny script before the tracker that keeps your calls in a list and
sends them once the tracker is ready:

```haskell
config {configQueueStub = True}
```

The stub prints even where the tag is off (in development, with
`configEnabled = Just False`, or with no site id). Then only the stub prints:
no tracker and no page props. So you can always call `privatus.track(...)`. In
development the calls just wait in the queue and are never sent. The stub
itself is `queueStub`.

### See the results

* [Funnels](https://privatusanalytics.com/docs/features/funnels): how many
  people go from one step to the next.
* [Click maps](https://privatusanalytics.com/docs/features/click-maps): where
  people click.
* [Goals](https://privatusanalytics.com/docs/features/goals): turn an event
  into a goal to count conversions.
* [Events](https://privatusanalytics.com/docs/events): every custom event and
  its props.

## Yesod

Yesod's hamlet templates build blaze-html, so the blaze helpers work as they
are. Keep the config in your foundation type:

```haskell
data App = App {appPrivatus :: Config, ...}
```

In `defaultLayout`, add the tag to the head. `analyticsTagFor` gets the WAI
request, so your `configRequestProps` runs too:

```haskell
defaultLayout widget = do
  app <- getYesod
  request <- waiRequest
  tag <- liftIO (analyticsTagFor (appPrivatus app) defaultTagOptions request)
  pc <- widgetToPageContent widget
  withUrlRenderer
    [hamlet|
      $doctype 5
      <html>
        <head>
          <title>#{pageTitle pc}
          #{preEscapedToMarkup tag}
          ^{pageHead pc}
        <body>
          ^{pageBody pc}
    |]
```

For events and click maps, hamlet takes a list of attribute pairs with
`*{...}`, which is just what `eventData` and `clickData` give:

```hamlet
<button *{eventData "Report exported" [("format", "csv")]}>Export
<a href=@{PricingR} *{clickData "pricing.cta"}>See plans
```

Hamlet escapes the values for you. If your Content Security Policy uses a
nonce, pass it in `tagNonce`. Or wrap the whole app
with `privatusMiddleware` in `makeApplication` instead of changing the layout.

## Servant

Servant serves HTML through `servant-lucid` or `servant-blaze`. Use the lucid
or blaze helpers in the page you return:

```haskell
type API = Get '[HTML] (Html ())

server :: Config -> Server API
server config = pure $ html_ $ do
  head_ (analyticsTag_ config defaultTagOptions)
  body_ (button_ (eventAttrs_ "Report exported" [("format", "csv")]) "Export")
```

Servant handlers do not see the WAI request, so `configRequestProps` is not
used there. Pass request props through `tagProps` instead, or wrap the
application with the middleware, which does get the request:

```haskell
main = do
  config <- loadConfig
  run 8080 (privatusMiddleware config (serve (Proxy @API) (server config)))
```

## Privacy

The script sets no cookies and stores nothing in the browser. The event, click
and props helpers only print HTML attributes and a small script. The package
never sends anything from your server and never reads IP addresses or user
agents. Keep people out of your props and event props: no names, emails or
user ids. See the [privacy
documentation](https://privatusanalytics.com/docs/privacy) for what is
collected.

If you have a privacy policy, it should say which tools handle your visitors' data. You can paste this:

> This website uses [Privatus Analytics](https://privatusanalytics.com/privacy-analytics) to count visits. It
> does not use cookies and does not follow you from one website to another. Your IP address is used for a moment
> to count visits and is never stored.

Change it to fit your site. The [privacy policy generator](https://privatusanalytics.com/tools/privacy-policy-generator)
makes a longer version with your site's name in it.

## Development

The checks run in Docker so your local GHC does not matter:

```sh
./run-docker.sh
```

It runs the hspec tests, hlint, an ormolu format check, `cabal check`,
`cabal sdist` and haddock in the `haskell:9.6` image. The cabal store is kept
in a Docker volume, so only the first run is slow.

## Contributing

Bug reports and pull requests are welcome at
https://github.com/Privatus-Analytics/haskell.

## License

MIT. See [LICENSE](LICENSE). Privatus Analytics is a product of Two Phase LLC,
Wyoming, USA.
