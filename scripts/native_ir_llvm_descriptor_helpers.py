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
