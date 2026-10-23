# Pristine 2x2 band comparison

Checked: 2026-09-10.

Both calculations completed through `pw.x` and `bands.x` with `JOB DONE.`
They used the same fresh stage-06 SCF density, relaxed geometry, cutoffs,
pseudopotentials, number of bands, and Gamma-M-K-Gamma path. The only intended
difference was the occupation setting in the band-path calculation.

| Method | Occupations | Fermi reference (eV) | VBM relative to Fermi (eV) | CBM relative to Fermi (eV) | Path-sampled gap (eV) |
| --- | --- | ---: | ---: | ---: | ---: |
| Cold | `smearing='cold'`, `degauss=0.01 Ry` | -1.880500 | -0.718100 | 0.834800 | 1.552900 |
| Fixed | `occupations='fixed'` | -1.880500 | -0.718100 | 0.834800 | 1.552900 |

The cold and fixed `bands.dat.gnu` files are byte-for-byte identical. All
3,782 sampled eigenvalues have a maximum absolute energy difference of
`0 eV` at the precision written by `bands.x`. Therefore, the occupation
choice did not affect this fixed-potential pristine band calculation.

## Current visual comparison

The cold- and fixed-occupation band structures look the same at the current
plot scale. This agrees with the point-by-point numerical comparison above.
For now, retain the cold result as the visual reference and the fixed result
as the confirming comparison.

This is a gap sampled along the selected Gamma-M-K-Gamma path, not proof of a
full-Brillouin-zone fundamental gap.
