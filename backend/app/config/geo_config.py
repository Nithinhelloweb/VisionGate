from typing import List, Tuple

DEFAULT_OUTER_COORDS: Tuple[Tuple[float, float], ...] = (
    (11.040730, 77.073717),
    (11.040865, 77.075121),
    (11.039733, 77.075201),
    (11.039529, 77.075786),
    (11.038500, 77.075892),
    (11.038551, 77.073616),
)

DEFAULT_INNER_COORDS: Tuple[Tuple[float, float], ...] = (
    (11.039537, 77.075328),
    (11.039554, 77.075895),
    (11.038858, 77.075912),
    (11.038501, 77.074908),
)


def get_default_outer() -> List[Tuple[float, float]]:
    """Return default outer geo-fence coordinates as a list."""
    return list(DEFAULT_OUTER_COORDS)


def get_default_inner() -> List[Tuple[float, float]]:
    """Return default inner geo-fence coordinates as a list."""
    return list(DEFAULT_INNER_COORDS)