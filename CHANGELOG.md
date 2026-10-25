# Changelog

## 1.0.0 - 2026-10-25

- Initial release.
- `analyticsTag`, `analyticsTagBS` and `analyticsTagFor` print the script tag.
- `Config` with site id, script host, modules, excluded paths, domains,
  single-page app mode, manual mode, extra attributes and more. `loadConfig`
  reads `PRIVATUS_SITE_ID`, `PRIVATUS_SCRIPT_HOST` and `PRIVATUS_ENV` or
  `APP_ENV`.
- Prints nothing outside production by default.
- `eventData`, `eventAttrs`, `clickData` and `clickAttr` for custom events and
  click map names.
- Page props: `configProps`, `configRequestProps` and `tagProps`. They print the
  `privatusPageProps` script and `data-props`.
- `configQueueStub`, so `privatus.track` calls made before the tracker loads are
  kept.
- `PrivatusAnalytics.Wai.privatusMiddleware` adds the tag to the head of HTML
  responses, with the Content Security Policy nonce when there is one.
- Helpers for lucid (`PrivatusAnalytics.Lucid`) and blaze-html
  (`PrivatusAnalytics.Blaze`).
