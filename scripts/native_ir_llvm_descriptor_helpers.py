"""Descriptor provenance helpers for LLVM-native lowering."""


def const_int_value(consts, value):
    item = consts.get(value)
    if not item or item[0] != "int":
        return None
    try:
        return int(item[1])
    except Exception:
        return None


def const_key_value(consts, value):
    item = consts.get(value)
    if not item:
        return None
    kind, raw = item
    if kind in ("string", "int", "bool", "nil"):
        return kind, raw
    return None


def derived_const_value(consts, op):
    kind = op.get("kind")
    result = op.get("result")
    if result is None:
        return None
    if kind == "binary" and op.get("op") == "+":
        left = consts.get(op.get("left"))
        right = consts.get(op.get("right"))
        if left and right and left[0] == "string" and right[0] == "string":
            return "string", f"{left[1]}{right[1]}"
        return None
    if kind != "runtime_helper_call":
        return None
    name = op.get("name")
    args = op.get("args", [])
    if name not in ("oren_string_slice", "oren_string_slice_unchecked") or len(args) < 3:
        return None
    source = consts.get(args[0])
    start = const_int_value(consts, args[1])
    end = const_int_value(consts, args[2])
    if not source or source[0] != "string" or start is None or end is None:
        return None
    raw = source[1]
    try:
        raw.encode("ascii")
    except UnicodeEncodeError:
        return None
    if start < 0 or end < start or end > len(raw):
        return None
    return "string", raw[start:end]


def intersect_origin_envs(envs):
    if not envs:
        return {}
    keys = set(envs[0])
    for env in envs[1:]:
        keys &= set(env)
    out = {}
    for key in keys:
        value = envs[0][key]
        if all(env.get(key) == value for env in envs[1:]):
            out[key] = value
    return out


def apply_list_element_fact(
    container,
    index,
    result,
    consts,
    strings,
    lists,
    bytes_values,
    maps,
    value_list_origin,
    value_map_origin,
    origin_elements,
    mutated_origins,
):
    elem_idx = const_int_value(consts, index)
    origin = value_list_origin.get(container)
    if elem_idx is None or origin is None or origin in mutated_origins:
        return
    source = origin_elements.get(origin, {}).get(elem_idx)
    if source is None:
        return
    if source in strings:
        strings.add(result)
        return
    if source in lists:
        lists.add(result)
        source_origin = value_list_origin.get(source)
        if source_origin is not None:
            value_list_origin[result] = source_origin
        return
    if source in bytes_values:
        bytes_values.add(result)
        return
    if source in maps:
        maps.add(result)
        source_origin = value_map_origin.get(source)
        if source_origin is not None:
            value_map_origin[result] = source_origin


def apply_map_element_fact(
    container,
    index,
    result,
    consts,
    strings,
    lists,
    bytes_values,
    maps,
    value_list_origin,
    value_map_origin,
    map_origin_elements,
):
    key = const_key_value(consts, index)
    origin = value_map_origin.get(container)
    if key is None or origin is None:
        return
    source = map_origin_elements.get(origin, {}).get(key)
    if source is None:
        return
    if source in strings:
        strings.add(result)
        return
    if source in lists:
        lists.add(result)
        source_origin = value_list_origin.get(source)
        if source_origin is not None:
            value_list_origin[result] = source_origin
        return
    if source in bytes_values:
        bytes_values.add(result)
        return
    if source in maps:
        maps.add(result)
        source_origin = value_map_origin.get(source)
        if source_origin is not None:
            value_map_origin[result] = source_origin
