# Mortar Scoop bucket

[Scoop](https://scoop.sh) manifests for [Mortar](https://mortar.rethunk.tech/), the desktop mod manager for PC games.

```powershell
scoop bucket add mortar https://github.com/Rethunk-Tech/scoop-bucket
scoop install mortar/mortar
```

`scoop update mortar` keeps it current; Mortar's own updater stays off when Scoop installed it. Every manifest pins the SHA-256 of each download, taken from the release's `SHA256SUMS` after checking its signature against the Mortar packages key (`D8B1 C4C2 05C5 FB36 33CB  8B99 00B7 5959 B637 DCB5`). A scheduled workflow moves the manifest to each new release.
