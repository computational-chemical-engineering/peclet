# peclet.morton — Morton/Z-order arithmetic

Vectorised Morton (Z-order) codes with O(1) arithmetic directly in Morton space.

!!! note
    Auto-generated from the installed module docstrings. Drive simulations from Python; the full C++ API is on each repo's Doxygen site.

## `peclet.morton`

peclet.morton - fast Morton (Z-order) codes with arithmetic, for NumPy.

This is a thin `ctypes` wrapper over the C++ `morton` library. Every
operation is vectorised: it runs over whole NumPy arrays in compiled code, so
there is no per-element Python overhead.

Supported configurations (dimensions x bits-per-axis):

    2D: 32, 16        3D: 21, 16

Codes are always returned as `uint64`.

Example
-------
>>> import numpy as np
>>> from peclet.morton import encode, decode, shift
>>> x = np.array([1, 2, 3], dtype=np.uint32)
>>> y = np.array([4, 5, 6], dtype=np.uint32)
>>> codes = encode(x, y, bits=32)
>>> xb = shift(codes, axis=0, delta=+1, dims=2, bits=32)  # move +1 in x, no decode
>>> decode(xb, dims=2, bits=32)
(array([2, 3, 4], dtype=uint32), array([4, 5, 6], dtype=uint32))

### `add_sat`
```
Add `delta` (signed) to one axis, *saturating* at the grid bounds [0, 2**bits - 1].

Unlike `shift` (which wraps), coordinates clamp instead of wrapping.
```

### `all_neighbors`
```
The `3**dims - 1` Moore neighbours of each code. Returns an `(N, 3**dims - 1)` array.
```

### `box_count`
```
Number of cells in the inclusive box [lo, hi].
```

### `box_zorder`
```
All Morton codes in the inclusive box [lo, hi], sorted in Z-order.
```

### `decode`
```
Decode Morton codes back into a tuple of `dims` coordinate arrays.
```

### `encode`
```
Interleave coordinate arrays into Morton codes (uint64).

Pass 2 or 3 equally sized integer arrays (one per axis).
```

### `face_neighbors`
```
The `2*dims` von-Neumann (face) neighbours of each code.

Returns an `(N, 2*dims)` uint64 array; columns are `[-x, +x, -y, +y(, -z, +z)]` (wrapping).
```

### `neighbor`
```
One-cell neighbour along `axis` in direction `dir` (+1 or -1), in Morton space.

The named O(1) form of `shift(delta=+/-1)`; coordinates wrap modulo 2**bits.
```

### `shift`
```
Add `delta` to one axis of each code, in Morton space (no decode/encode).

`delta` may be negative. Coordinates wrap modulo 2**bits.
```

### `sub_sat`
```
Subtract `delta` (>= 0) from one axis, *saturating* at 0. See `add_sat`.
```

### `try_add`
```
Bounds-checked axis add. Returns `(out, ok)`.

`ok` is a bool array: `True` where the move stayed in [0, 2**bits - 1]; where `False`,
the corresponding `out` entry is the *unchanged* input code (no wrap, no clamp).
```

### `try_sub`
```
Bounds-checked axis subtract (delta >= 0). Returns `(out, ok)`. See `try_add`.
```

