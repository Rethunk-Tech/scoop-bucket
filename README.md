# Mortar Scoop bucket

[Scoop](https://scoop.sh) manifests for [Mortar](https://mortar.rethunk.tech/), the desktop mod manager for PC games.

```powershell
scoop bucket add mortar https://github.com/Rethunk-Tech/scoop-bucket
scoop install mortar/mortar
```

`scoop update mortar` keeps it current; Mortar's own updater stays off when Scoop installed it. Every manifest pins the SHA-256 of each download, taken from the release's `SHA256SUMS` after checking its signature against the Mortar packages key (`3283 6046 06CA E229 5D47 6F98 83BC 8751 EE6F 773D`). A scheduled workflow moves the manifest to each new release.
