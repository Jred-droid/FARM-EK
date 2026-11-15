"""
Servidor de FARM-EK (clima + cultivos)
======================================
1) CLIMA: la app de Flutter le pide el clima a ESTE servidor, y este servidor se
   lo pide a Meteomatics con tu usuario y contraseña. Así las credenciales nunca
   quedan dentro de la app (en una página web cualquiera podría verlas).
2) CULTIVOS: lee el archivo BDPLANS_cultivos.csv (debe estar en la MISMA carpeta
   que este archivo) y le manda a la app los datos de cada cultivo.
3) ACTUALIZADOR: cada 5 minutos vuelve a pedir el clima de las parcelas que la
   app consultó recientemente, para que los datos nunca se queden viejos.
4) PROYECTOS: guarda las parcelas en el archivo proyectos.json, en la carpeta
   CARPETA_PROYECTOS (ver más abajo).
5) ROTACIÓN: simulación Monte Carlo (montecarlo.py) con el clima REAL de cada
   ubicación. La primera vez que se pide una ubicación, el servidor descarga su
   año completo de Meteomatics (12 consultas) y lo guarda en la carpeta "climas/".
   Las siguientes veces lo lee del archivo, sin volver a consultar. No dependen del navegador: se ven desde cualquier navegador o equipo.

Uso:
    pip install flask flask-cors requests numpy
    (configura METEOMATICS_USER y METEOMATICS_PASS, ver abajo)
    python servidor_clima.py

Prueba en el navegador:
    http://localhost:5000/api/clima?lat=21.110829&lon=-89.608860
    http://localhost:5000/api/clima?lat=21.110829&lon=-89.608860&forzar=1   (ignora la copia guardada)
    http://localhost:5000/api/cultivos
    http://localhost:5000/api/estado    (muestra qué está actualizando el servidor)
    http://localhost:5000/api/proyectos (lista de parcelas guardadas)
    http://localhost:5000/api/rotacion?lat=21.110829&lon=-89.608860&ph=7.3&profundidad=1
    http://localhost:5000/api/rotacion?lat=21.110829&lon=-89.608860&ph=7.3&profundidad=1&riego=1
    (opcionales: &humedad=33&mo=7.76&arcilla=35&arena=38&elevacion=9&pendiente=1.36)
"""

import csv
import json
import os
import threading
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path

import requests
from flask import Flask, jsonify, request
from flask_cors import CORS

import montecarlo as mc

USUARIO = os.getenv("METEOMATICS_USER")
PASSWORD = os.getenv("METEOMATICS_PASS")
BASE_URL = "https://api.meteomatics.com"

# Parámetros que ya probaron en su script (se piden en UNA sola llamada)
PRINCIPALES = {
    "temperatura": "t_2m:C",
    "humedad": "relative_humidity_2m:p",
    "precipitacion": "precip_1h:mm",
    "evaporacion": "evapotranspiration_1h:mm",
    "radiacion": "clear_sky_rad:W",
    "uv": "uv:idx",
}

# Parámetros extra: si alguno no viene en su plan, simplemente se omite
EXTRAS = {
    "maxima": "t_max_2m_24h:C",
    "minima": "t_min_2m_24h:C",
    "viento": "wind_speed_10m:kmh",
    "simbolo": "weather_symbol_1h:idx",
    "amanecer": "sunrise:sql",
    "atardecer": "sunset:sql",
}

# ------------------------------------------------------------
# Actualizador automático
# ------------------------------------------------------------
INTERVALO_ACTUALIZACION = 5 * 60   # Cada cuánto se renuevan los datos (segundos)
CACHE_SEGUNDOS = 4 * 60            # Una copia guardada vale 4 min (menos que el intervalo)
UBICACION_ACTIVA_SEGUNDOS = 30 * 60  # Solo se actualizan parcelas consultadas en los últimos 30 min

_cache = {}                 # (lat, lon) -> (momento, datos)
_ubicaciones_activas = {}   # (lat, lon) -> momento de la última consulta de la app
_candado = threading.Lock() # Evita que el actualizador y las consultas choquen
_estado_actualizador = {"ultimaVuelta": None, "actualizadas": 0, "errores": 0}

app = Flask(__name__)
CORS(app)  # Permite que la app Flutter (localhost:8080) llame a este servidor


def consultar(parametros, lat, lon):
    """Pide varios parámetros en una sola llamada y regresa {parametro: valor}."""
    url = f"{BASE_URL}/now/{','.join(parametros)}/{lat},{lon}/json"
    resp = requests.get(url, auth=(USUARIO, PASSWORD), timeout=20)
    resp.raise_for_status()
    return {
        d["parameter"]: d["coordinates"][0]["dates"][0]["value"]
        for d in resp.json()["data"]
    }


def consultar_extras(lat, lon):
    """Intenta todos los extras juntos; si falla, uno por uno."""
    try:
        valores = consultar(list(EXTRAS.values()), lat, lon)
        return {clave: valores.get(param) for clave, param in EXTRAS.items()}
    except requests.RequestException:
        resultado = {}
        for clave, param in EXTRAS.items():
            try:
                resultado[clave] = consultar([param], lat, lon).get(param)
            except requests.RequestException:
                resultado[clave] = None  # No disponible en su plan
        return resultado


def pedir_clima_meteomatics(lat, lon):
    """Pide el clima completo a Meteomatics y lo guarda en la copia (cache)."""
    valores = consultar(list(PRINCIPALES.values()), lat, lon)
    resultado = {clave: valores.get(param) for clave, param in PRINCIPALES.items()}
    resultado.update(consultar_extras(lat, lon))
    resultado["consultado"] = datetime.now(timezone.utc).isoformat()
    with _candado:
        _cache[(lat, lon)] = (time.time(), resultado)
    return resultado


@app.get("/api/clima")
def clima():
    # 1. Validar coordenadas
    try:
        lat = round(float(request.args["lat"]), 4)
        lon = round(float(request.args["lon"]), 4)
    except (KeyError, ValueError):
        return jsonify(error="Faltan lat y lon válidos"), 400

    if not USUARIO or not PASSWORD:
        return jsonify(error="Configura METEOMATICS_USER y METEOMATICS_PASS en el servidor"), 500

    forzar = request.args.get("forzar", "0").lower() in ("1", "true", "si", "sí")

    # 2. Registrar la parcela para que el actualizador la mantenga al día
    with _candado:
        _ubicaciones_activas[(lat, lon)] = time.time()
        guardado = _cache.get((lat, lon))

    # 3. Copia guardada reciente (a menos que pidan forzar)
    if not forzar and guardado and time.time() - guardado[0] < CACHE_SEGUNDOS:
        return jsonify(guardado[1])

    # 4. Consultar Meteomatics
    try:
        resultado = pedir_clima_meteomatics(lat, lon)
    except requests.HTTPError as e:
        codigo = e.response.status_code if e.response is not None else "?"
        if codigo == 401:
            return jsonify(error="Usuario o contraseña de Meteomatics incorrectos"), 502
        return jsonify(error=f"Meteomatics respondió con error {codigo}"), 502
    except requests.RequestException:
        # Si falla la conexión pero hay una copia anterior, se manda esa
        if guardado:
            return jsonify(guardado[1])
        return jsonify(error="No se pudo conectar con Meteomatics"), 502

    return jsonify(resultado)


# ------------------------------------------------------------
# Hilo que trabaja en segundo plano: renueva el clima cada 5 minutos
# ------------------------------------------------------------
def ciclo_actualizador():
    while True:
        time.sleep(INTERVALO_ACTUALIZACION)
        ahora = time.time()

        with _candado:
            # Se olvidan las parcelas que nadie ha consultado en los últimos 30 min
            for clave in [k for k, t in _ubicaciones_activas.items() if ahora - t > UBICACION_ACTIVA_SEGUNDOS]:
                del _ubicaciones_activas[clave]
            pendientes = list(_ubicaciones_activas)

        for lat, lon in pendientes:
            try:
                pedir_clima_meteomatics(lat, lon)
                _estado_actualizador["actualizadas"] += 1
                print(f"[actualizador] Clima renovado para {lat}, {lon}")
            except requests.RequestException as e:
                _estado_actualizador["errores"] += 1
                print(f"[actualizador] No se pudo renovar {lat}, {lon}: {e}")

        _estado_actualizador["ultimaVuelta"] = datetime.now(timezone.utc).isoformat()


def iniciar_actualizador():
    hilo = threading.Thread(target=ciclo_actualizador, daemon=True)  # daemon: se cierra junto con el servidor
    hilo.start()
    print(f"Actualizador encendido: renueva el clima cada {INTERVALO_ACTUALIZACION // 60} minutos")


@app.get("/api/estado")
def estado():
    with _candado:
        activas = [{"lat": lat, "lon": lon} for lat, lon in _ubicaciones_activas]
    return jsonify(
        intervaloMinutos=INTERVALO_ACTUALIZACION // 60,
        parcelasActivas=activas,
        **_estado_actualizador,
    )


# ============================================================
# CULTIVOS: datos del archivo BDPLANS_cultivos.csv
# ============================================================
ARCHIVO_CULTIVOS = Path(__file__).with_name("BDPLANS_cultivos.csv")

# Cultivos de la app -> "ID EcoPort" de su fila en el archivo.
# Si quieres usar otra variedad, cambia el ID por el de la fila que prefieras.
CULTIVOS_APP = {
    "Chile": "618",        # Capsicum annuum
    "Manzana": "1407",     # Malus domestica
    "Tomate": "1379",      # Lycopersicon esculentum
    "Zanahoria": "871",    # Daucus carota
    "Maíz": "238663",      # Zea mays ssp. mays
    "Aguacate": "17644",   # Persea americana ssp. mexican
    "Plátano": "7849",     # Musa acuminata x balbisiana
    "Naranja": "720",      # Citrus sinensis
    "Limón": "2242",       # Citrus aurantifolia (limón mexicano)
    "Fresa": "1112",       # Fragaria x ananassa
    "Sandía": None,        # No viene en el archivo
    "Uva": "2160",         # Vitis vinifera
    "Lechuga": "1313",     # Lactuca sativa var. capitata
    "Cebolla": "364",      # Allium cepa
    "Papa": "1971",        # Solanum tuberosum
}

# Nombre que usa la app -> nombre de la columna en el archivo
CAMPOS = {
    "cientifico": "Nombre científico",
    "nombresComunes": "Nombres comunes",
    "grupo": "Grupo de cultivo",
    "formaVida": "Forma de vida",
    "cicloVida": "Ciclo de vida",
    "tempMinAbs": "Temp. mín. absoluta (°C)",
    "tempMinOpt": "Temp. mín. óptima (°C)",
    "tempMaxOpt": "Temp. máx. óptima (°C)",
    "tempMaxAbs": "Temp. máx. absoluta (°C)",
    "tempLetal": "Temp. letal / helada (°C)",
    "lluviaMinAbs": "Lluvia mín. absoluta (mm/año)",
    "lluviaMinOpt": "Lluvia mín. óptima (mm/año)",
    "lluviaMaxOpt": "Lluvia máx. óptima (mm/año)",
    "lluviaMaxAbs": "Lluvia máx. absoluta (mm/año)",
    "phMinAbs": "pH mín. absoluto",
    "phMinOpt": "pH mín. óptimo",
    "phMaxOpt": "pH máx. óptimo",
    "phMaxAbs": "pH máx. absoluto",
    "cicloMin": "Ciclo mín. (días)",
    "cicloMax": "Ciclo máx. (días)",
    "altitudMax": "Altitud máx. (m)",
    "texturaOpt": "Textura de suelo óptima",
    "texturaTol": "Textura de suelo tolerada",
    "drenajeOpt": "Drenaje óptimo",
    "drenajeTol": "Drenaje tolerado",
    "fertilidadOpt": "Fertilidad óptima",
    "fertilidadTol": "Fertilidad tolerada",
    "salinidadOpt": "Salinidad óptima",
    "salinidadTol": "Salinidad tolerada",
    "profundidadOpt": "Profundidad de suelo óptima",
    "profundidadTol": "Profundidad de suelo tolerada",
}
NUMERICOS = {
    "tempMinAbs", "tempMinOpt", "tempMaxOpt", "tempMaxAbs", "tempLetal",
    "lluviaMinAbs", "lluviaMinOpt", "lluviaMaxOpt", "lluviaMaxAbs",
    "phMinAbs", "phMinOpt", "phMaxOpt", "phMaxAbs",
    "cicloMin", "cicloMax", "altitudMax",
}


def numero(texto):
    """Convierte '1.200' -> 1200.0 y '6,5' -> 6.5 (formato del archivo). Vacío -> None."""
    t = (texto or "").strip()
    if not t:
        return None
    try:
        return float(t.replace(".", "").replace(",", "."))
    except ValueError:
        return None


def leer_archivo():
    """Lee el CSV (separado por ';'). Acepta el archivo original o uno guardado de nuevo desde Excel."""
    for codificacion in ("utf-8-sig", "latin-1"):
        try:
            with open(ARCHIVO_CULTIVOS, encoding=codificacion, newline="") as f:
                return {fila["ID EcoPort"].strip(): fila for fila in csv.DictReader(f, delimiter=";")}
        except UnicodeDecodeError:
            continue
    return {}


def cargar_cultivos():
    filas = leer_archivo()
    resultado = {}
    for nombre, id_ecoport in CULTIVOS_APP.items():
        fila = filas.get(id_ecoport) if id_ecoport else None
        if fila is None:
            continue
        datos = {}
        for clave, columna in CAMPOS.items():
            valor = fila.get(columna)
            datos[clave] = numero(valor) if clave in NUMERICOS else ((valor or "").strip() or None)
        resultado[nombre] = datos
    return resultado


@app.get("/api/cultivos")
def cultivos():
    if not ARCHIVO_CULTIVOS.exists():
        return jsonify(error=f"No se encontró {ARCHIVO_CULTIVOS.name} en la carpeta del servidor"), 500
    # Se lee en cada consulta: si editas el archivo, la app recibe los cambios al recargar
    return jsonify(cultivos=cargar_cultivos())


# ============================================================
# PROYECTOS: guardados en proyectos.json (carpeta del servidor)
# ============================================================
# Carpeta donde se guarda proyectos.json. Cámbiala aquí si quieres otra ubicación.
CARPETA_PROYECTOS = Path(r"C:\Users\tblbe\ek_xploration\lib")
ARCHIVO_PROYECTOS = CARPETA_PROYECTOS / "proyectos.json"
_candado_proyectos = threading.Lock()


def leer_proyectos():
    """Regresa la lista de proyectos del archivo (vacía si aún no existe)."""
    if not ARCHIVO_PROYECTOS.exists():
        return []
    try:
        with open(ARCHIVO_PROYECTOS, encoding="utf-8") as f:
            datos = json.load(f)
        return datos if isinstance(datos, list) else []
    except (json.JSONDecodeError, OSError):
        # Si el archivo se dañó, se respalda y se empieza de nuevo
        respaldo = ARCHIVO_PROYECTOS.with_suffix(".danado.json")
        ARCHIVO_PROYECTOS.replace(respaldo)
        print(f"AVISO: proyectos.json estaba dañado; se movió a {respaldo.name}")
        return []


def escribir_proyectos(proyectos):
    """Escribe primero un archivo temporal y luego lo renombra: así nunca queda a medias."""
    ARCHIVO_PROYECTOS.parent.mkdir(parents=True, exist_ok=True)  # Crea la carpeta si no existe
    temporal = ARCHIVO_PROYECTOS.with_suffix(".tmp")
    with open(temporal, "w", encoding="utf-8") as f:
        json.dump(proyectos, f, ensure_ascii=False, indent=2)
    temporal.replace(ARCHIVO_PROYECTOS)


@app.get("/api/proyectos")
def listar_proyectos():
    with _candado_proyectos:
        proyectos = leer_proyectos()
    proyectos.sort(key=lambda p: p.get("fechaCreacion", ""), reverse=True)
    return jsonify(proyectos=proyectos)


@app.put("/api/proyectos/<id_proyecto>")
def guardar_proyecto(id_proyecto):
    """Crea el proyecto o lo reemplaza si ya existe uno con el mismo id."""
    proyecto = request.get_json(silent=True)
    if not isinstance(proyecto, dict) or not proyecto.get("nombre"):
        return jsonify(error="Proyecto inválido"), 400
    proyecto["id"] = id_proyecto

    with _candado_proyectos:
        proyectos = [p for p in leer_proyectos() if p.get("id") != id_proyecto]
        proyectos.append(proyecto)
        escribir_proyectos(proyectos)
    return jsonify(ok=True, proyecto=proyecto)


@app.delete("/api/proyectos/<id_proyecto>")
def eliminar_proyecto(id_proyecto):
    with _candado_proyectos:
        proyectos = leer_proyectos()
        restantes = [p for p in proyectos if p.get("id") != id_proyecto]
        if len(restantes) == len(proyectos):
            return jsonify(error="No existe ese proyecto"), 404
        escribir_proyectos(restantes)
    return jsonify(ok=True)


# ============================================================
# ROTACIÓN DE CULTIVOS: simulación Monte Carlo
# ============================================================
CARPETA_SERVIDOR = Path(__file__).parent


CARPETA_CLIMAS = CARPETA_SERVIDOR / "climas"
ANIO_CLIMA = 2025                              # Año completo que se usa como base
ZONA_MEXICO = timezone(timedelta(hours=-6))    # Días en hora de México (UTC-6)

# Mismos parámetros horarios que API_AÑO_MONTECARLO.py
PARAMETROS_ANUALES = {
    "t_2m:C": "temperatura",
    "precip_1h:mm": "precipitacion",
    "evapotranspiration_1h:mm": "evaporacion",
}
_candado_climas = threading.Lock()


def archivo_clima_ubicacion(lat, lon):
    """Nombre del archivo de clima de una ubicación (redondeada a ~1 km)."""
    return CARPETA_CLIMAS / f"clima_{ANIO_CLIMA}_{lat:.2f}_{lon:.2f}.csv"


def descargar_clima_anual(lat, lon):
    """
    Descarga el año ANIO_CLIMA hora por hora (un pedido por mes), lo resume en
    un valor por día y lo guarda en climas/clima_AÑO_lat_lon.csv.
    """
    horas = {}  # fecha -> {"temperatura": [...], "precipitacion": [...], "evaporacion": [...]}
    for mes in range(1, 13):
        inicio_local = datetime(ANIO_CLIMA, mes, 1, tzinfo=ZONA_MEXICO)
        fin_local = datetime(ANIO_CLIMA + (mes == 12), mes % 12 + 1, 1, tzinfo=ZONA_MEXICO) - timedelta(hours=1)
        inicio = inicio_local.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        fin = fin_local.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        url = f"{BASE_URL}/{inicio}--{fin}:PT1H/{','.join(PARAMETROS_ANUALES)}/{lat},{lon}/json"
        resp = requests.get(url, auth=(USUARIO, PASSWORD), timeout=90)
        resp.raise_for_status()
        for serie in resp.json()["data"]:
            nombre = PARAMETROS_ANUALES[serie["parameter"]]
            for d in serie["coordinates"][0]["dates"]:
                if d["value"] is None:
                    continue
                momento = datetime.fromisoformat(d["date"].replace("Z", "+00:00")).astimezone(ZONA_MEXICO)
                horas.setdefault(momento.date(), {}).setdefault(nombre, []).append(d["value"])
        print(f"[clima] {lat:.2f}, {lon:.2f}: mes {mes}/12 descargado")

    filas = []
    for dia in sorted(horas):
        h = horas[dia]
        temps = h.get("temperatura", [])
        if dia.year != ANIO_CLIMA or not temps:
            continue
        filas.append({
            "fecha": dia.isoformat(),
            "temp_promedio_C": round(sum(temps) / len(temps), 2),
            "temp_min_C": round(min(temps), 2),
            "temp_max_C": round(max(temps), 2),
            "precipitacion_mm": round(sum(h.get("precipitacion", [])), 2),
            "evaporacion_mm": round(sum(h.get("evaporacion", [])), 2),
        })

    archivo = archivo_clima_ubicacion(lat, lon)
    archivo.parent.mkdir(parents=True, exist_ok=True)
    with open(archivo, "w", newline="", encoding="utf-8-sig") as f:
        escritor = csv.DictWriter(f, fieldnames=filas[0].keys())
        escritor.writeheader()
        escritor.writerows(filas)
    return archivo


def clima_diario_para(lat, lon):
    """
    Archivo de clima de ESA ubicación: si ya existe se usa; si no, se descarga.
    Regresa (ruta, mensaje de error o None).
    """
    archivo = archivo_clima_ubicacion(lat, lon)
    if archivo.exists():
        return archivo, None
    if not USUARIO or not PASSWORD:
        return None, "faltan las credenciales de Meteomatics para descargar el clima de esta ubicación"
    with _candado_climas:  # Evita descargar la misma ubicación dos veces a la vez
        if archivo.exists():
            return archivo, None
        try:
            return descargar_clima_anual(lat, lon), None
        except (requests.RequestException, KeyError, ValueError, IndexError) as e:
            return None, f"no se pudo descargar el clima de esta ubicación ({e})"


def clima_aproximado_mensual(lat, lon):
    """Respaldo si no hay CSV: clima aproximado ajustado a la temperatura de hoy."""
    actual = None
    if USUARIO and PASSWORD:
        try:
            actual = consultar(["t_2m:C"], lat, lon).get("t_2m:C")
        except requests.RequestException:
            pass
    temp, lluvia = mc.clima_aproximado(lat, actual, datetime.now().month - 1)
    return list(temp), list(lluvia)


@app.get("/api/rotacion")
def rotacion():
    try:
        lat = float(request.args["lat"])
        lon = float(request.args["lon"])
        ph = float(request.args.get("ph", 6.5))
        profundidad = float(request.args.get("profundidad", 1.0))
        n_sim = max(100, min(int(request.args.get("n", 1000)), 5000))
        largo = max(2, min(int(request.args.get("largo", 4)), 4))  # 4 cultivos por defecto
        riego = request.args.get("riego", "0").lower() in ("1", "true", "si", "sí")

        def opcional(nombre):
            valor = request.args.get(nombre)
            return float(valor) if valor not in (None, "") else None

        # Datos extra del suelo (de la API de suelo). Si no vienen, no se toman en cuenta.
        suelo = mc.SueloParcela(
            ph=ph,
            profundidad=profundidad,
            humedad=opcional("humedad"),
            materia_organica=opcional("mo"),
            arcilla=opcional("arcilla"),
            arena=opcional("arena"),
            elevacion=opcional("elevacion"),
            pendiente=opcional("pendiente"),
        )
    except (KeyError, ValueError):
        return jsonify(error="Parámetros inválidos (se necesitan lat y lon)"), 400

    if not ARCHIVO_CULTIVOS.exists():
        return jsonify(error=f"No se encontró {ARCHIVO_CULTIVOS.name} en la carpeta del servidor"), 500

    cultivos_sim = mc.cargar_candidatos(leer_archivo())
    parametros = dict(
        mes_inicio=datetime.now().month - 1,
        ph=ph,
        profundidad=profundidad,
        n_sim=n_sim,
        largo=largo,
        top=12,  # Se prueban los 12 cultivos más aptos (con 4: 11,880 rotaciones en ~5 s)
        riego=riego,
        suelo=suelo,
    )

    # Clima REAL de la ubicación de esta parcela (se descarga la primera vez)
    csv_clima, aviso = clima_diario_para(lat, lon)
    if csv_clima is not None:
        clima = mc.cargar_clima_diario(csv_clima)
        resultado = mc.simular_rotaciones(cultivos_sim, clima_diario=clima, **parametros)
        resultado["archivoClima"] = csv_clima.name
        resultado["climaBase"] = mc.resumen_clima_diario(clima)
    else:
        temp, lluvia = clima_aproximado_mensual(lat, lon)
        resultado = mc.simular_rotaciones(cultivos_sim, temp, lluvia, **parametros)
        resultado["archivoClima"] = None
        resultado["avisoClima"] = aviso
        resultado["climaBase"] = {"temperatura": [round(t, 1) for t in temp], "lluvia": [round(l, 1) for l in lluvia]}

    resultado["ubicacionClima"] = {"lat": round(lat, 2), "lon": round(lon, 2)}
    return jsonify(resultado)


MODO_DEBUG = True

if __name__ == "__main__":
    print("Servidor de FARM-EK en http://localhost:5000")
    if not ARCHIVO_CULTIVOS.exists():
        print(f"AVISO: no se encontró {ARCHIVO_CULTIVOS.name} junto a este archivo")
    print(f"Proyectos guardados en: {ARCHIVO_PROYECTOS}")
    print(f"Climas por ubicación (rotación) en: {CARPETA_CLIMAS}")

    # En modo debug Flask arranca el programa dos veces (uno vigila los cambios del código);
    # el actualizador solo se enciende en el proceso que atiende a la app.
    if not MODO_DEBUG or os.environ.get("WERKZEUG_RUN_MAIN") == "true":
        iniciar_actualizador()

    app.run(host="0.0.0.0", port=5000, debug=MODO_DEBUG)
