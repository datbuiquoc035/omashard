# Sky Shards (Omarchy plugin)

An [Omarchy](../omarchy) plugin that lets you see [Shard Eruptions](https://sky-children-of-the-light.fandom.com/wiki/Shard_Eruptions) from the game *Sky: Children of the Light* — their color, time, and location.

## What it does

Every day the game spawns shards at a specific time and place. This plugin surfaces that information at a glance, showing the shard's type (Red or Black), its timings, and its location.

## Development

**Requirements:** Node.js >= 18, pnpm >= 8.

```bash
# enable pnpm once
corepack enable

# install dependencies
pnpm install

# development server
pnpm dev

# type-check + build
pnpm build
```

The `build` script downloads the latest translations before compiling. To build without downloading translations, use `pnpm buildonly`.

## Upstream

This is a plugin build of the original [Sky Shards](https://github.com/PlutoyDev/sky-shards.git) repository.

## License

You can do whatever you want with the code; a link back to this repository or website is appreciated.

> [!IMPORTANT]
> Assets in `/public/infographics/*`, `/public/ext/*` and `/public/emojis/*` are **not** covered by this license — they are not created by me.

[MIT](./LICENSE)
