"""
Simulación Monte Carlo de rotaciones de cultivo para FARM-EK
============================================================

Idea general
------------
1. Se toma el clima REAL de la parcela: 365 días del archivo clima_AÑO_diario.csv
   (temperatura, mínima, lluvia y evapotranspiración de Meteomatics).
   Si no hay archivo, se usa un clima aproximado de 12 meses.
2. Se generan MILES de futuros posibles. Cada mes de cada futuro se arma
   sacando al azar DÍAS REALES de ese mismo mes del año medido (remuestreo o
   "bootstrap"), y se le suma una pequeña variación entre años (un año más
   caluroso o más seco que el medido).
3. En cada futuro se "siembra" una rotación (ej. Pepino -> Calabaza -> Frijol):
   cada cultivo dura un número de días al azar dentro de su ciclo y se califica
   según la temperatura, la lluvia, el pH y la profundidad del suelo que le tocaron,
   comparados con sus rangos óptimos y absolutos del archivo BDPLANS.
4. Una rotación tiene ÉXITO en un futuro si TODOS sus cultivos superan el umbral.
5. % de éxito = futuros con éxito / futuros simulados. Gana la rotación con mayor %.

Reglas agronómicas incluidas
----------------------------
- Repetir la misma familia botánica seguida se penaliza fuerte (plagas y enfermedades).
- Después de una leguminosa (frijol, chícharo, cacahuate...) el siguiente cultivo
  recibe un pequeño bono (la leguminosa deja nitrógeno en el suelo).
"""

from __future__ import annotations

import itertools
import math
from dataclasses import dataclass

import numpy as np

# ------------------------------------------------------------
# Cultivos candidatos para rotación (anuales y comunes en México)
# nombre científico (como en BDPLANS) -> (nombre en español, familia botánica)
# Puedes agregar o quitar cultivos aquí.
# ------------------------------------------------------------
CANDIDATOS = {
    "Phaseolus vulgaris": ("Frijol", "Fabaceae"),
    "Vigna unguiculata": ("Frijol caupí", "Fabaceae"),
    "Arachis hypogaea": ("Cacahuate", "Fabaceae"),
    "Glycine max": ("Soya", "Fabaceae"),
    "Pisum sativum": ("Chícharo", "Fabaceae"),
    "Cicer arietinum": ("Garbanzo", "Fabaceae"),
    "Cucumis sativus": ("Pepino", "Cucurbitaceae"),
    "Cucurbita moschata": ("Calabaza", "Cucurbitaceae"),
    "Cucurbita pepo": ("Calabacita", "Cucurbitaceae"),
    "Cucumis melo": ("Melón", "Cucurbitaceae"),
    "Zea mays ssp. mays": ("Maíz", "Poaceae"),
    "Sorghum bicolor": ("Sorgo", "Poaceae"),
    "Lycopersicon esculentum": ("Tomate", "Solanaceae"),
    "Capsicum annuum": ("Chile", "Solanaceae"),
    "Solanum melongena": ("Berenjena", "Solanaceae"),
    "Solanum tuberosum": ("Papa", "Solanaceae"),
    "Daucus carota": ("Zanahoria", "Apiaceae"),
    "Allium cepa": ("Cebolla", "Amaryllidaceae"),
    "Lactuca sativa var. capitata": ("Lechuga", "Asteraceae"),
    "Spinacia oleracea": ("Espinaca", "Amaranthaceae"),
    "Beta vulgaris var. cicla": ("Acelga", "Amaranthaceae"),
    "Amaranthus hybridus": ("Quelite / amaranto", "Amaranthaceae"),
    "Brassica oleracea var. capitata": ("Repollo", "Brassicaceae"),
    "Brassica oleracea var. botrytis": ("Coliflor", "Brassicaceae"),
    "Brassica oleracea var. italica": ("Brócoli", "Brassicaceae"),
    "Raphanus sativus": ("Rábano", "Brassicaceae"),
    "Abelmoschus esculentus": ("Okra", "Malvaceae"),
}

DIAS_MES = 30.4
MAX_MESES_CULTIVO = 8  # Ciclos más largos se recortan (la rotación busca cultivos de temporada)


def numero(texto):
    """'1.200' -> 1200.0 ; '6,5' -> 6.5 ; vacío -> None (formato del archivo)."""
    t = (texto or "").strip()
    if not t:
        return None
    try:
        return float(t.replace(".", "").replace(",", "."))
    except ValueError:
        return None


@dataclass
class CultivoSim:
    nombre: str
    cientifico: str
    familia: str
    leguminosa: bool
    t_min_abs: float
    t_min_opt: float
    t_max_opt: float
    t_max_abs: float
    t_letal: float | None
    ll_min_abs: float
    ll_min_opt: float
    ll_max_opt: float
    ll_max_abs: float
    ph_min_abs: float
    ph_min_opt: float
    ph_max_opt: float
    ph_max_abs: float
    ciclo_min: float
    ciclo_max: float
    prof_necesaria: float  # metros


def _profundidad_m(texto: str | None) -> float:
    t = (texto or "").lower()
    if "profunda" in t:
        return 1.5
    if "media" in t:
        return 0.5
    if "somera" in t:
        return 0.2
    return 0.2


def cargar_candidatos(filas_por_id: dict) -> list[CultivoSim]:
    """Convierte las filas del CSV (ya leídas por el servidor) en cultivos para simular."""
    por_nombre = {fila["Nombre científico"].strip(): fila for fila in filas_por_id.values()}
    cultivos = []
    for cientifico, (nombre, familia) in CANDIDATOS.items():
        fila = por_nombre.get(cientifico)
        if fila is None:
            continue
        valores = {
            "t_min_abs": numero(fila.get("Temp. mín. absoluta (°C)")),
            "t_min_opt": numero(fila.get("Temp. mín. óptima (°C)")),
            "t_max_opt": numero(fila.get("Temp. máx. óptima (°C)")),
            "t_max_abs": numero(fila.get("Temp. máx. absoluta (°C)")),
            "ll_min_abs": numero(fila.get("Lluvia mín. absoluta (mm/año)")),
            "ll_min_opt": numero(fila.get("Lluvia mín. óptima (mm/año)")),
            "ll_max_opt": numero(fila.get("Lluvia máx. óptima (mm/año)")),
            "ll_max_abs": numero(fila.get("Lluvia máx. absoluta (mm/año)")),
            "ph_min_abs": numero(fila.get("pH mín. absoluto")),
            "ph_min_opt": numero(fila.get("pH mín. óptimo")),
            "ph_max_opt": numero(fila.get("pH máx. óptimo")),
            "ph_max_abs": numero(fila.get("pH máx. absoluto")),
            "ciclo_min": numero(fila.get("Ciclo mín. (días)")),
            "ciclo_max": numero(fila.get("Ciclo máx. (días)")),
        }
        if any(v is None for v in valores.values()):
            continue  # Le faltan datos clave
        cultivos.append(
            CultivoSim(
                nombre=nombre,
                cientifico=cientifico,
                familia=familia,
                leguminosa=(fila.get("Grupo de cultivo") or "").startswith("Leguminosas"),
                t_letal=numero(fila.get("Temp. letal / helada (°C)")),
                prof_necesaria=_profundidad_m(fila.get("Profundidad de suelo óptima")),
                **valores,
            )
        )
    return cultivos


# ------------------------------------------------------------
# Clima
# ------------------------------------------------------------
def clima_aproximado(latitud: float, temp_actual: float | None, mes_actual: int) -> tuple[np.ndarray, np.ndarray]:
    """
    Clima "normal" aproximado cuando no hay historial de Meteomatics:
    temperatura en forma de onda anual (más amplitud lejos del ecuador)
    y 1,000 mm de lluvia al año con temporada de lluvias en verano.
    """
    amplitud = float(np.clip(0.18 * abs(latitud), 1.5, 14))
    pico = 6 if latitud >= 0 else 0  # Mes más caluroso: julio (norte) o enero (sur)
    meses = np.arange(12)
    onda = np.cos(2 * np.pi * (meses - pico) / 12)
    media = 22.0
    if temp_actual is not None:
        # Ajusta la media para que el mes actual coincida con la temperatura de hoy
        media = temp_actual - amplitud * onda[mes_actual]
    temp = media + amplitud * onda
    lluvia_rel = 1 + 0.8 * np.cos(2 * np.pi * (meses - (7 if latitud >= 0 else 1)) / 12)
    lluvia = 1000 * lluvia_rel / lluvia_rel.sum()
    return temp, lluvia


def generar_futuros(temp_base, lluvia_base, mes_inicio, n, meses, rng):
    """
    Futuros a partir de un clima MENSUAL aproximado (cuando no hay CSV diario).
    - Cada futuro tiene una anomalía anual de temperatura (año caluroso / fresco).
    - Cada mes tiene ruido propio.
    - La lluvia se multiplica por factores aleatorios (años secos / húmedos).
    """
    temp_base = np.asarray(temp_base, dtype=float)
    lluvia_base = np.asarray(lluvia_base, dtype=float)
    idx = (mes_inicio + np.arange(meses)) % 12
    anomalia_anual = rng.normal(0, 1.0, size=(n, 1))
    ruido_mensual = rng.normal(0, 1.4, size=(n, meses))
    temp = temp_base[idx][None, :] + anomalia_anual + ruido_mensual

    factor_anual = rng.lognormal(0, 0.25, size=(n, 1))
    factor_mensual = rng.lognormal(0, 0.45, size=(n, meses))
    lluvia = lluvia_base[idx][None, :] * factor_anual * factor_mensual
    return {
        "temp": temp,
        "lluvia": lluvia,
        "tmin": temp - 6,  # Mínima aproximada: ~6 °C abajo del promedio
        "et": None,        # Sin dato de evapotranspiración
        "fuente": "clima aproximado (12 meses)",
    }


# ------------------------------------------------------------
# Clima REAL diario (archivo clima_AÑO_diario.csv)
# ------------------------------------------------------------
def cargar_clima_diario(ruta):
    """
    Lee el CSV que genera API_AÑO_MONTECARLO.py y agrupa los días por mes.
    Regresa {mes (0-11): {"temp": array, "tmin": array, "lluvia": array, "et": array}}
    """
    import csv

    por_mes = {m: {"temp": [], "tmin": [], "lluvia": [], "et": []} for m in range(12)}
    with open(ruta, encoding="utf-8-sig", newline="") as f:
        for fila in csv.DictReader(f):
            try:
                mes = int(fila["fecha"][5:7]) - 1
                temp = float(fila["temp_promedio_C"])
            except (KeyError, ValueError):
                continue  # Día sin dato de temperatura
            def leer(columna, por_defecto):
                try:
                    return float(fila.get(columna) or por_defecto)
                except ValueError:
                    return por_defecto
            por_mes[mes]["temp"].append(temp)
            por_mes[mes]["tmin"].append(leer("temp_min_C", temp - 6))
            por_mes[mes]["lluvia"].append(leer("precipitacion_mm", 0.0))
            por_mes[mes]["et"].append(leer("evaporacion_mm", 0.0))

    vacios = [m + 1 for m in range(12) if not por_mes[m]["temp"]]
    if vacios:
        raise ValueError(f"El archivo no tiene datos de los meses {vacios}")
    return {m: {k: np.array(v) for k, v in datos.items()} for m, datos in por_mes.items()}


def resumen_clima_diario(dias_por_mes):
    """Promedio mensual de temperatura y lluvia/evapotranspiración total por mes (para mostrar)."""
    return {
        "temperatura": [round(float(dias_por_mes[m]["temp"].mean()), 1) for m in range(12)],
        "lluvia": [round(float(dias_por_mes[m]["lluvia"].mean() * DIAS_MES), 1) for m in range(12)],
        "evapotranspiracion": [round(float(dias_por_mes[m]["et"].mean() * DIAS_MES), 1) for m in range(12)],
    }


def generar_futuros_reales(dias_por_mes, mes_inicio, n, meses, rng):
    """
    Futuros armados con DÍAS REALES (remuestreo / bootstrap):
    para cada futuro y cada mes, se sacan al azar 30 días reales de ese mismo mes
    y con ellos se calcula la temperatura promedio, la mínima, la lluvia y la
    evapotranspiración del mes. Así se conserva la variación real del clima.

    Como un solo año no muestra si el siguiente será más caluroso o más seco,
    se agrega una variación entre años: ±0.8 °C y lluvia ±25 % (aprox.).
    """
    temp = np.empty((n, meses))
    tmin = np.empty((n, meses))
    lluvia = np.empty((n, meses))
    et = np.empty((n, meses))

    dias_muestra = int(round(DIAS_MES))
    for k in range(meses):
        datos = dias_por_mes[(mes_inicio + k) % 12]
        idx = rng.integers(0, len(datos["temp"]), size=(n, dias_muestra))
        temp[:, k] = datos["temp"][idx].mean(axis=1)
        tmin[:, k] = datos["tmin"][idx].min(axis=1)
        lluvia[:, k] = datos["lluvia"][idx].sum(axis=1)
        et[:, k] = datos["et"][idx].sum(axis=1)

    anomalia_temp = rng.normal(0, 0.8, size=(n, 1))   # Año más caluroso o más fresco
    factor_lluvia = rng.lognormal(0, 0.25, size=(n, 1))  # Año más seco o más lluvioso
    return {
        "temp": temp + anomalia_temp,
        "tmin": tmin + anomalia_temp,
        "lluvia": lluvia * factor_lluvia,
        "et": et * (1 + 0.03 * anomalia_temp),  # Más calor -> un poco más de evaporación
        "fuente": "clima real diario (Meteomatics, 365 días) con remuestreo",
    }


def trapecio(x, abs_min, opt_min, opt_max, abs_max):
    """1 dentro del rango óptimo; baja en línea recta hasta 0 en los límites absolutos."""
    x = np.asarray(x, dtype=float)
    subida = np.clip((x - abs_min) / max(opt_min - abs_min, 1e-9), 0, 1)
    bajada = np.clip((abs_max - x) / max(abs_max - opt_max, 1e-9), 0, 1)
    return np.minimum(subida, bajada)


# ------------------------------------------------------------
# Calificación de un cultivo en todos los futuros a la vez
# ------------------------------------------------------------
def calificar_cultivo(c: CultivoSim, inicio, futuros, ph, profundidad, riego, rng):
    """
    inicio: arreglo (n,) con el mes en que se siembra en cada futuro.
    Devuelve (puntaje (n,), meses que dura (n,), riego necesario en mm (n,)).
    """
    temp, lluvia, tmin, et = futuros["temp"], futuros["lluvia"], futuros["tmin"], futuros["et"]
    n = temp.shape[0]
    # Duración al azar dentro del ciclo (más probable cerca del mínimo)
    dias = rng.triangular(c.ciclo_min, c.ciclo_min + 0.25 * (c.ciclo_max - c.ciclo_min), c.ciclo_max, size=n)
    meses = np.clip(np.ceil(dias / DIAS_MES).astype(int), 1, MAX_MESES_CULTIVO)

    filas = np.arange(n)
    suma_t = np.zeros(n)
    suma_ll = np.zeros(n)
    deficit_agua = np.zeros(n)  # mm que faltan (evapotranspiración - lluvia)
    minimo_t = np.full(n, np.inf)
    for k in range(MAX_MESES_CULTIVO):
        activo = k < meses
        col = np.minimum(inicio + k, temp.shape[1] - 1)
        suma_t += np.where(activo, temp[filas, col], 0)
        ll_k = lluvia[filas, col]
        suma_ll += np.where(activo, ll_k, 0)
        minimo_t = np.where(activo, np.minimum(minimo_t, tmin[filas, col]), minimo_t)
        if et is not None:
            deficit_agua += np.where(activo, np.maximum(et[filas, col] - ll_k, 0), 0)

    temp_media = suma_t / meses
    lluvia_anual_equiv = suma_ll * 12 / meses

    p_temp = trapecio(temp_media, c.t_min_abs, c.t_min_opt, c.t_max_opt, c.t_max_abs)
    p_lluvia = trapecio(lluvia_anual_equiv, c.ll_min_abs, c.ll_min_opt, c.ll_max_opt, c.ll_max_abs)
    if riego:
        p_lluvia = np.maximum(p_lluvia, 0.85)  # Con riego la falta de lluvia casi no afecta
    p_ph = float(trapecio(ph, c.ph_min_abs, c.ph_min_opt, c.ph_max_opt, c.ph_max_abs))
    p_prof = 1.0 if profundidad >= c.prof_necesaria else 0.7

    # Promedio geométrico ponderado: si un factor es 0, el cultivo fracasa
    puntaje = (
        np.power(p_temp, 0.45)
        * np.power(p_lluvia, 0.25)
        * (p_ph ** 0.20)
        * (p_prof ** 0.10)
    )

    # Heladas: si la mínima del periodo baja de la temperatura letal del cultivo
    if c.t_letal is not None:
        helada = minimo_t <= c.t_letal
        puntaje = np.where(helada, puntaje * 0.3, puntaje)

    return puntaje, meses, deficit_agua


# ------------------------------------------------------------
# Simulación principal
# ------------------------------------------------------------
def simular_rotaciones(
    cultivos: list[CultivoSim],
    temp_base=None,
    lluvia_base=None,
    mes_inicio: int = 0,
    ph: float = 6.5,
    profundidad: float = 1.0,
    n_sim: int = 1000,
    largo: int = 3,
    top: int = 10,
    umbral: float = 0.6,
    riego: bool = False,
    semilla: int | None = None,
    clima_diario=None,
):
    """
    clima_diario: resultado de cargar_clima_diario(...). Si se da, los futuros se
    arman con días reales; si no, con el clima mensual temp_base / lluvia_base.
    """
    rng = np.random.default_rng(semilla)
    horizonte = largo * MAX_MESES_CULTIVO + 1

    if clima_diario is not None:
        futuros = generar_futuros_reales(clima_diario, mes_inicio, n_sim, horizonte, rng)
    else:
        futuros = generar_futuros(temp_base, lluvia_base, mes_inicio, n_sim, horizonte, rng)

    # 1) Pre-filtro: los 'top' cultivos con mejor puntaje promedio sembrando en cualquier mes
    calificaciones = []
    for c in cultivos:
        puntajes = []
        for mes in range(0, 12, 2):
            p, _, _ = calificar_cultivo(c, np.full(n_sim, mes), futuros, ph, profundidad, riego, rng)
            puntajes.append(p.mean())
        calificaciones.append((float(np.mean(puntajes)), c))
    calificaciones.sort(key=lambda x: x[0], reverse=True)
    elegidos = [c for puntaje, c in calificaciones[:top] if puntaje > 0.05]

    if len(elegidos) < largo:
        return {"ranking": [], "mensaje": "No hay suficientes cultivos adecuados para esta parcela."}

    # 2) Probar todas las rotaciones posibles (sin repetir cultivo) en los mismos futuros
    resultados = []
    for rotacion in itertools.permutations(elegidos, largo):
        inicio = np.zeros(n_sim, dtype=int)
        exito_todos = np.ones(n_sim, dtype=bool)
        riego_total = np.zeros(n_sim)
        puntajes, exitos_cultivo = [], []
        anterior = None

        for c in rotacion:
            p, meses, deficit = calificar_cultivo(c, inicio, futuros, ph, profundidad, riego, rng)
            if anterior is not None:
                if anterior.familia == c.familia:
                    p = p * 0.65  # Misma familia seguida: más plagas y enfermedades del suelo
                if anterior.leguminosa and not c.leguminosa:
                    p = np.minimum(p * 1.10, 1.0)  # Nitrógeno que deja la leguminosa
            ok = p >= umbral
            exito_todos &= ok
            puntajes.append(p.mean())
            exitos_cultivo.append(ok.mean())
            riego_total += deficit
            inicio = inicio + meses
            anterior = c

        resultados.append(
            {
                "rotacion": [c.nombre for c in rotacion],
                "cientificos": [c.cientifico for c in rotacion],
                "exito": round(float(exito_todos.mean()), 4),
                "puntaje": round(float(np.mean(puntajes)), 4),
                "exitoPorCultivo": [round(float(e), 4) for e in exitos_cultivo],
                "mesesPromedio": round(float(inicio.mean()), 1),
                # Agua que habría que regar en toda la rotación (mm = litros por m²)
                "riegoNecesarioMm": round(float(riego_total.mean()), 0) if futuros["et"] is not None else None,
            }
        )

    # Orden: más % de éxito; si empatan, mejor puntaje; si empatan, la que necesita menos riego
    resultados.sort(key=lambda r: (r["exito"], r["puntaje"], -(r["riegoNecesarioMm"] or 0)), reverse=True)
    mejor = resultados[0]
    mensaje = (
        f"La rotación {' → '.join(mejor['rotacion'])} es la que mejores resultados tuvo, "
        f"con un {mejor['exito'] * 100:.0f}% de éxito en {n_sim:,} futuros simulados"
        f"{' (con riego)' if riego else ' (sin riego)'}."
    )
    return {
        "mensaje": mensaje,
        "mejor": mejor,
        "ranking": resultados[:10],
        "simulaciones": n_sim,
        "rotacionesEvaluadas": len(resultados),
        "cultivosConsiderados": [c.nombre for c in elegidos],
        "umbral": umbral,
        "riego": riego,
        "fuenteClima": futuros["fuente"],
    }
