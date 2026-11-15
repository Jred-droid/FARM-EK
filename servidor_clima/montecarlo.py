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
   comparando lo que le tocó con lo que pide en el archivo BDPLANS:

   CLIMA (cambia en cada futuro)               peso
     - Temperatura promedio vs. rango óptimo     30 %
     - Calor extremo (temperatura máxima)         5 %
     - Lluvia vs. rango de lluvia                10 %
     - Balance de agua: lluvia + agua guardada
       en el suelo vs. evapotranspiración        15 %
     - Heladas (temperatura mínima vs. letal)    castigo x0.3
   SUELO DE LA PARCELA (fijo)
     - pH vs. pH óptimo                          15 %
     - Profundidad vs. profundidad óptima         7 %
     - Textura (arcilla/limo/arena) vs. textura   7 %
     - Fertilidad (materia orgánica)              6 %
     - Elevación vs. altitud máxima               3 %
     - Pendiente del terreno                      2 %
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
    textura_opt: frozenset = frozenset()  # {"pesada (arcillosa)", "media", ...}
    textura_tol: frozenset = frozenset()
    fertilidad_opt: str | None = None     # "baja" / "moderada" / "alta"
    fertilidad_tol: str | None = None
    altitud_max: float | None = None      # metros


def _profundidad_m(texto: str | None) -> float:
    t = (texto or "").lower()
    if "profunda" in t:
        return 1.5
    if "media" in t:
        return 0.5
    if "somera" in t:
        return 0.2
    return 0.2


def _categorias(texto: str | None) -> frozenset:
    """'media, ligera (arenosa)' -> {'media', 'ligera (arenosa)'}"""
    return frozenset(p.strip() for p in (texto or "").split(",") if p.strip())


def _primera(texto: str | None) -> str | None:
    """'moderada, baja' -> 'moderada' (se toma la primera categoría)"""
    partes = [p.strip() for p in (texto or "").split(",") if p.strip()]
    return partes[0] if partes else None


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
                textura_opt=_categorias(fila.get("Textura de suelo óptima")),
                textura_tol=_categorias(fila.get("Textura de suelo tolerada")),
                fertilidad_opt=_primera(fila.get("Fertilidad óptima")),
                fertilidad_tol=_primera(fila.get("Fertilidad tolerada")),
                altitud_max=numero(fila.get("Altitud máx. (m)")),
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
        "tmax": temp + 6,  # Máxima aproximada: ~6 °C arriba del promedio
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

    por_mes = {m: {"temp": [], "tmin": [], "tmax": [], "lluvia": [], "et": []} for m in range(12)}
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
            por_mes[mes]["tmax"].append(leer("temp_max_C", temp + 6))
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
    tmax = np.empty((n, meses))
    lluvia = np.empty((n, meses))
    et = np.empty((n, meses))

    dias_muestra = int(round(DIAS_MES))
    for k in range(meses):
        datos = dias_por_mes[(mes_inicio + k) % 12]
        idx = rng.integers(0, len(datos["temp"]), size=(n, dias_muestra))
        temp[:, k] = datos["temp"][idx].mean(axis=1)
        tmin[:, k] = datos["tmin"][idx].min(axis=1)
        tmax[:, k] = datos["tmax"][idx].mean(axis=1)  # Máxima típica del mes
        lluvia[:, k] = datos["lluvia"][idx].sum(axis=1)
        et[:, k] = datos["et"][idx].sum(axis=1)

    anomalia_temp = rng.normal(0, 0.8, size=(n, 1))   # Año más caluroso o más fresco
    factor_lluvia = rng.lognormal(0, 0.25, size=(n, 1))  # Año más seco o más lluvioso
    return {
        "temp": temp + anomalia_temp,
        "tmin": tmin + anomalia_temp,
        "tmax": tmax + anomalia_temp,
        "lluvia": lluvia * factor_lluvia,
        "et": et * (1 + 0.03 * anomalia_temp),  # Más calor -> un poco más de evaporación
        "fuente": "clima real diario (Meteomatics, 365 días) con remuestreo",
    }


# ------------------------------------------------------------
# Suelo de la parcela (de la API de suelo / Earth Engine)
# ------------------------------------------------------------
@dataclass
class SueloParcela:
    ph: float
    profundidad: float                      # m
    humedad: float | None = None            # % de agua a capacidad de campo
    materia_organica: float | None = None   # %
    arcilla: float | None = None            # %
    arena: float | None = None              # %
    elevacion: float | None = None          # m
    pendiente: float | None = None          # grados

    @property
    def clase_textura(self) -> str | None:
        """Clase de textura con las mismas palabras que usa BDPLANS."""
        if self.materia_organica is not None and self.materia_organica >= 20:
            return "orgánica"
        if self.arcilla is None or self.arena is None:
            return None
        if self.arcilla >= 35:
            return "pesada (arcillosa)"
        if self.arena >= 65:
            return "ligera (arenosa)"
        return "media"

    @property
    def fertilidad(self) -> str | None:
        """Fertilidad según la materia orgánica: baja (<2 %), moderada (2-4 %), alta (>4 %)."""
        if self.materia_organica is None:
            return None
        if self.materia_organica < 2:
            return "baja"
        if self.materia_organica < 4:
            return "moderada"
        return "alta"

    @property
    def reserva_agua_mm(self) -> float:
        """
        Agua que el suelo puede guardar y ceder a las raíces (mm).
        Capacidad de campo (%) x profundidad de raíces (hasta 1 m) x 50 % aprovechable.
        """
        if self.humedad is None:
            return 0.0
        return self.humedad / 100 * min(self.profundidad, 1.0) * 1000 * 0.5


_NIVEL_FERTILIDAD = {"baja": 0, "moderada": 1, "alta": 2}


def factores_suelo(c: "CultivoSim", suelo: SueloParcela) -> dict:
    """Calificación (0-1) de cada característica fija del suelo para un cultivo."""
    f = {}
    f["ph"] = float(trapecio(suelo.ph, c.ph_min_abs, c.ph_min_opt, c.ph_max_opt, c.ph_max_abs))
    f["profundidad"] = 1.0 if suelo.profundidad >= c.prof_necesaria else 0.7

    # Textura: ideal = 1, tolerada = 0.8, otra = 0.55
    clase = suelo.clase_textura
    if clase is None or not c.textura_opt or "amplia" in c.textura_opt or clase in c.textura_opt:
        f["textura"] = 1.0
    elif clase in c.textura_tol:
        f["textura"] = 0.8
    else:
        f["textura"] = 0.55

    # Fertilidad: si la parcela llega a la óptima = 1, a la tolerada = 0.8, si no = 0.6
    nivel = _NIVEL_FERTILIDAD.get(suelo.fertilidad or "")
    opt = _NIVEL_FERTILIDAD.get(c.fertilidad_opt or "")
    tol = _NIVEL_FERTILIDAD.get(c.fertilidad_tol or "", opt)
    if nivel is None or opt is None:
        f["fertilidad"] = 1.0
    elif nivel >= opt:
        f["fertilidad"] = 1.0
    elif tol is not None and nivel >= tol:
        f["fertilidad"] = 0.8
    else:
        f["fertilidad"] = 0.6

    # Altitud: arriba de la altitud máxima del cultivo, crece mal
    if suelo.elevacion is None or c.altitud_max is None:
        f["altitud"] = 1.0
    else:
        f["altitud"] = 1.0 if suelo.elevacion <= c.altitud_max else 0.4

    # Pendiente: terrenos muy inclinados se erosionan y son difíciles de trabajar
    if suelo.pendiente is None or suelo.pendiente <= 8:
        f["pendiente"] = 1.0
    elif suelo.pendiente <= 15:
        f["pendiente"] = 0.85
    else:
        f["pendiente"] = 0.6
    return f


# Peso de cada factor en el puntaje (suman 1)
PESOS = {
    "temperatura": 0.30,
    "calor": 0.05,
    "lluvia": 0.10,
    "balance_agua": 0.15,
    "ph": 0.15,
    "profundidad": 0.07,
    "textura": 0.07,
    "fertilidad": 0.06,
    "altitud": 0.03,
    "pendiente": 0.02,
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
def calificar_cultivo(c: CultivoSim, inicio, futuros, suelo: SueloParcela, riego, rng, f_suelo=None, detalle=False):
    """
    inicio: arreglo (n,) con el mes en que se siembra en cada futuro.
    Devuelve (puntaje (n,), meses que dura (n,), riego necesario en mm (n,)).
    Con detalle=True agrega un 4.º valor: promedio de cada factor (0 a 1) para explicar el resultado.
    """
    temp, lluvia, tmin, et = futuros["temp"], futuros["lluvia"], futuros["tmin"], futuros["et"]
    tmax = futuros.get("tmax")
    n = temp.shape[0]
    # Duración al azar dentro del ciclo (más probable cerca del mínimo)
    dias = rng.triangular(c.ciclo_min, c.ciclo_min + 0.25 * (c.ciclo_max - c.ciclo_min), c.ciclo_max, size=n)
    meses = np.clip(np.ceil(dias / DIAS_MES).astype(int), 1, MAX_MESES_CULTIVO)

    filas = np.arange(n)
    suma_t = np.zeros(n)
    suma_tmax = np.zeros(n)
    suma_ll = np.zeros(n)
    suma_et = np.zeros(n)
    minimo_t = np.full(n, np.inf)
    for k in range(MAX_MESES_CULTIVO):
        activo = k < meses
        col = np.minimum(inicio + k, temp.shape[1] - 1)
        suma_t += np.where(activo, temp[filas, col], 0)
        if tmax is not None:
            suma_tmax += np.where(activo, tmax[filas, col], 0)
        suma_ll += np.where(activo, lluvia[filas, col], 0)
        if et is not None:
            suma_et += np.where(activo, et[filas, col], 0)
        minimo_t = np.where(activo, np.minimum(minimo_t, tmin[filas, col]), minimo_t)

    temp_media = suma_t / meses
    lluvia_anual_equiv = suma_ll * 12 / meses

    # --- Clima ---
    p_temp = trapecio(temp_media, c.t_min_abs, c.t_min_opt, c.t_max_opt, c.t_max_abs)

    # Calor extremo: si la máxima típica pasa la máxima absoluta del cultivo, va bajando
    if tmax is not None:
        tmax_media = suma_tmax / meses
        p_calor = np.clip(1 - (tmax_media - c.t_max_abs) / 8, 0, 1)
    else:
        p_calor = np.ones(n)

    p_lluvia = trapecio(lluvia_anual_equiv, c.ll_min_abs, c.ll_min_opt, c.ll_max_opt, c.ll_max_abs)

    # Balance de agua: (lluvia + agua guardada en el suelo) / lo que se evapora
    reserva = suelo.reserva_agua_mm
    if et is not None:
        demanda = np.maximum(suma_et, 1e-9)
        cobertura = np.minimum((suma_ll + reserva) / demanda, 1.0)
        p_balance = np.clip((cobertura - 0.3) / (0.8 - 0.3), 0, 1)  # 80 % cubierto = sin estrés
        riego_mm = np.maximum(suma_et - suma_ll - reserva, 0)
    else:
        p_balance = np.ones(n)
        riego_mm = np.zeros(n)

    if riego:
        p_lluvia = np.maximum(p_lluvia, 0.85)  # Con riego la falta de lluvia casi no afecta
        p_balance = np.ones(n)                 # El riego repone el agua que falta

    # --- Suelo (fijo para cada cultivo) ---
    fs = f_suelo if f_suelo is not None else factores_suelo(c, suelo)

    # Promedio geométrico ponderado: si un factor es 0, el cultivo fracasa
    puntaje = (
        np.power(p_temp, PESOS["temperatura"])
        * np.power(p_calor, PESOS["calor"])
        * np.power(p_lluvia, PESOS["lluvia"])
        * np.power(p_balance, PESOS["balance_agua"])
        * (fs["ph"] ** PESOS["ph"])
        * (fs["profundidad"] ** PESOS["profundidad"])
        * (fs["textura"] ** PESOS["textura"])
        * (fs["fertilidad"] ** PESOS["fertilidad"])
        * (fs["altitud"] ** PESOS["altitud"])
        * (fs["pendiente"] ** PESOS["pendiente"])
    )

    # Heladas: si la mínima del periodo baja de la temperatura letal del cultivo
    helada = (minimo_t <= c.t_letal) if c.t_letal is not None else np.zeros(n, dtype=bool)
    puntaje = np.where(helada, puntaje * 0.3, puntaje)

    if detalle:
        factores = {
            "temperatura": float(p_temp.mean()),
            "calor": float(p_calor.mean()),
            "lluvia": float(p_lluvia.mean()),
            "agua": float(p_balance.mean()),
            "ph": fs["ph"],
            "profundidad": fs["profundidad"],
            "textura": fs["textura"],
            "fertilidad": fs["fertilidad"],
            "altitud": fs["altitud"],
            "pendiente": fs["pendiente"],
            # 1 = nunca hubo helada; 0 = helada en todos los futuros
            "heladas": float(1 - helada.mean()),
        }
        return puntaje, meses, riego_mm, factores
    return puntaje, meses, riego_mm


# ------------------------------------------------------------
# Simulación principal
# ------------------------------------------------------------
def intervalo_confianza(p, n, z=1.96):
    """Intervalo de Wilson al 95 %: dónde estaría el % de éxito si se repitiera la simulación."""
    if n <= 0:
        return p, p
    den = 1 + z * z / n
    centro = (p + z * z / (2 * n)) / den
    margen = z * np.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / den
    return round(float(max(0.0, centro - margen)), 4), round(float(min(1.0, centro + margen)), 4)


def diversificar(resultados, largo, cuantas=10):
    """
    Elige rotaciones buenas pero VARIADAS:
      - cada rotación nueva comparte como máximo (largo - 2) cultivos con las ya elegidas
        (con 3 cultivos: máximo 1 en común; con 4: máximo 2),
      - un mismo cultivo no puede abrir más de 2 rotaciones.
    La mejor de todas siempre queda en primer lugar. Si no alcanzan, se completa con las mejores.
    """
    max_compartidos = max(1, largo - 2)
    elegidas, inicios = [], {}
    for r in resultados:
        cultivos = set(r["rotacion"])
        primero = r["rotacion"][0]
        if inicios.get(primero, 0) >= 2:
            continue
        if any(len(cultivos & set(e["rotacion"])) > max_compartidos for e in elegidas):
            continue
        elegidas.append(r)
        inicios[primero] = inicios.get(primero, 0) + 1
        if len(elegidas) == cuantas:
            return elegidas
    for r in resultados:  # Completar si hizo falta
        if len(elegidas) == cuantas:
            break
        if r not in elegidas:
            elegidas.append(r)
    return elegidas


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
    suelo: SueloParcela | None = None,
):
    """
    clima_diario: resultado de cargar_clima_diario(...). Si se da, los futuros se
    arman con días reales; si no, con el clima mensual temp_base / lluvia_base.
    suelo: datos completos de la parcela. Si no se da, solo se usan ph y profundidad.
    """
    rng = np.random.default_rng(semilla)
    if suelo is None:
        suelo = SueloParcela(ph=ph, profundidad=profundidad)
    # Calificación fija del suelo para cada cultivo (se calcula una sola vez)
    f_suelo = {c.cientifico: factores_suelo(c, suelo) for c in cultivos}
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
            p, _, _ = calificar_cultivo(c, np.full(n_sim, mes), futuros, suelo, riego, rng, f_suelo[c.cientifico])
            puntajes.append(p.mean())
        calificaciones.append((float(np.mean(puntajes)), c))
    calificaciones.sort(key=lambda x: x[0], reverse=True)
    elegidos = [c for puntaje, c in calificaciones[:top] if puntaje > 0.05]

    if len(elegidos) < largo:
        return {
            "ranking": [],
            "mensaje": (
                "Ninguna rotación es viable en esta parcela sin riego: el clima es demasiado seco o extremo "
                "para los cultivos candidatos. Prueba la opción con riego."
                if not riego else
                "No hay suficientes cultivos adecuados para el clima y el suelo de esta parcela."
            ),
            "simulaciones": n_sim,
            "rotacionesEvaluadas": 0,
            "cultivosConsiderados": [c.nombre for c in elegidos],
            "riego": riego,
            "fuenteClima": futuros["fuente"],
        }

    # 2) Probar TODAS las rotaciones posibles (sin repetir cultivo) en los mismos futuros.
    #    Se recorren como un árbol: las rotaciones que empiezan igual comparten el cálculo
    #    de sus primeros cultivos (mucho más rápido con rotaciones de 4).
    resultados = []

    def explorar(prefijo, inicio, exito_todos, riego_total, puntajes, exitos_cultivo, detalles, calendario):
        if len(prefijo) == largo:
            resultados.append(
                {
                    "rotacion": [c.nombre for c in prefijo],
                    "cientificos": [c.cientifico for c in prefijo],
                    "exito": round(float(exito_todos.mean()), 4),
                    "puntaje": round(float(np.mean(puntajes)), 4),
                    "exitoPorCultivo": [round(float(e), 4) for e in exitos_cultivo],
                    "mesesPromedio": round(float(inicio.mean()), 1),
                    # Agua que habría que regar en toda la rotación (mm = litros por m²)
                    "riegoNecesarioMm": round(float(riego_total.mean()), 0) if futuros["et"] is not None else None,
                    # Calificación del suelo de la parcela para cada cultivo (0 a 1)
                    "factoresSuelo": {c.nombre: {k: round(v, 2) for k, v in f_suelo[c.cientifico].items()} for c in prefijo},
                    # Por qué salió así: promedio de cada factor por cultivo (0 a 1)
                    "detalles": detalles,
                    # Mes típico de siembra (0 = enero) y meses que dura cada cultivo
                    "calendario": calendario,
                }
            )
            return

        anterior = prefijo[-1] if prefijo else None
        usados = {c.cientifico for c in prefijo}
        for c in elegidos:
            if c.cientifico in usados:
                continue
            p, meses, deficit, fac = calificar_cultivo(
                c, inicio, futuros, suelo, riego, rng, f_suelo[c.cientifico], detalle=True)
            efecto = 1.0  # Efecto del cultivo anterior
            if anterior is not None:
                if anterior.familia == c.familia:
                    p = p * 0.65  # Misma familia seguida: más plagas y enfermedades del suelo
                    efecto = 0.65
                if anterior.leguminosa and not c.leguminosa:
                    p = np.minimum(p * 1.10, 1.0)  # Nitrógeno que deja la leguminosa
                    efecto *= 1.10
            ok = p >= umbral
            fac = {k: round(v, 2) for k, v in fac.items()}
            fac["rotacion"] = round(efecto, 2)
            siembra = int(np.bincount((mes_inicio + inicio) % 12, minlength=12).argmax())
            cal = {"cultivo": c.nombre, "siembra": siembra, "meses": int(np.median(meses))}
            explorar(
                prefijo + [c],
                inicio + meses,
                exito_todos & ok,
                riego_total + deficit,
                puntajes + [p.mean()],
                exitos_cultivo + [ok.mean()],
                detalles + [{"cultivo": c.nombre, **fac}],
                calendario + [cal],
            )

    explorar([], np.zeros(n_sim, dtype=int), np.ones(n_sim, dtype=bool), np.zeros(n_sim), [], [], [], [])

    # Orden: más % de éxito; si empatan, mejor puntaje; si empatan, la que necesita menos riego
    resultados.sort(key=lambda r: (r["exito"], r["puntaje"], -(r["riegoNecesarioMm"] or 0)), reverse=True)

    # 3) Variedad: en lugar de mostrar 10 rotaciones casi iguales, se eligen las mejores
    #    que sean DISTINTAS entre sí (comparten pocos cultivos y no empiezan siempre igual).
    ranking = diversificar(resultados, largo, cuantas=10)

    # Rango de confianza del % de éxito (solo para las que se muestran)
    for r in ranking + [resultados[0]]:
        r["exitoMin"], r["exitoMax"] = intervalo_confianza(r["exito"], n_sim)

    mejor = resultados[0]
    mensaje = (
        f"La rotación {' → '.join(mejor['rotacion'])} es la que mejores resultados tuvo, "
        f"con un {mejor['exito'] * 100:.0f}% de éxito en {n_sim:,} futuros simulados"
        f"{' (con riego)' if riego else ' (sin riego)'}."
    )
    return {
        "mensaje": mensaje,
        "mejor": mejor,
        "ranking": ranking,
        "simulaciones": n_sim,
        "rotacionesEvaluadas": len(resultados),
        "cultivosConsiderados": [c.nombre for c in elegidos],
        "umbral": umbral,
        "riego": riego,
        "fuenteClima": futuros["fuente"],
        "suelo": {
            "ph": suelo.ph,
            "profundidad": suelo.profundidad,
            "textura": suelo.clase_textura,
            "fertilidad": suelo.fertilidad,
            "reservaAguaMm": round(suelo.reserva_agua_mm, 0),
            "elevacion": suelo.elevacion,
            "pendiente": suelo.pendiente,
        },
    }
