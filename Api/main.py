"""
API de Análisis de Suelo (FARM-EK)
==================================
Consulta datos de suelo y relieve en Google Earth Engine para un punto (lat, lon).

Instalación (solo la primera vez):
    py -m pip install fastapi uvicorn earthengine-api

Encender la API:
    py main.py
    (o también: uvicorn main:app --port 8000)

Probar en el navegador:
    http://localhost:8000/
    http://localhost:8000/suelo?lat=21.110829&lon=-89.608860

Publicarla con ngrok (en otra terminal):
    ngrok http --url=accent-petite-utensil.ngrok-free.dev 8000
"""

from pathlib import Path

import ee
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware

# ==================================
# EARTH ENGINE
# ==================================

SERVICE_ACCOUNT = "earth-engine-service@dark-furnace-436804-i6.iam.gserviceaccount.com"

# El archivo de la llave debe estar en la MISMA carpeta que este main.py
ARCHIVO_LLAVE = Path(__file__).with_name("dark-furnace-436804-i6-911135b21970.json")

credentials = ee.ServiceAccountCredentials(SERVICE_ACCOUNT, str(ARCHIVO_LLAVE))
ee.Initialize(credentials)

app = FastAPI(
    title="API de Análisis de Suelo",
    version="1.1",
)

# Permite que la app Flutter (web en localhost:8080, Windows o celular) llame a esta API
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# ------------------------
# DATASETS (se cargan una sola vez)
# ------------------------
PH = ee.Image("OpenLandMap/SOL/SOL_PH-H2O_USDA-4C1A2A_M/v02")
HUMEDAD = ee.Image("OpenLandMap/SOL/SOL_WATERCONTENT-33KPA_USDA-4B1C_M/v01")
ARCILLA = ee.Image("OpenLandMap/SOL/SOL_CLAY-WFRACTION_USDA-3A1A1A_M/v02")
ARENA = ee.Image("OpenLandMap/SOL/SOL_SAND-WFRACTION_USDA-3A1A1A_M/v02")
CARBONO = ee.Image("OpenLandMap/SOL/SOL_ORGANIC-CARBON_USDA-6A1C_M/v02")
DEM = ee.Image("USGS/SRTMGL1_003")

# Capa superficial (b0 = 0 cm) de cada dataset, todas juntas en una sola imagen.
# Así se hace UNA consulta para el suelo en lugar de cinco (mucho más rápido).
SUELO = ee.Image.cat([
    PH.select("b0").rename("ph"),
    HUMEDAD.select("b0").rename("humedad"),
    ARCILLA.select("b0").rename("arcilla"),
    ARENA.select("b0").rename("arena"),
    CARBONO.select("b0").rename("carbono"),
])

# Elevación y pendiente juntas (resolución de 30 m)
RELIEVE = ee.Image.cat([
    DEM.select("elevation"),
    ee.Terrain.slope(DEM).rename("pendiente"),
])


@app.get("/")
def inicio():
    return {"mensaje": "API de Suelo funcionando"}


@app.get("/suelo")
def obtener_suelo(lat: float, lon: float):
    if not (-90 <= lat <= 90 and -180 <= lon <= 180):
        raise HTTPException(status_code=400, detail="Coordenadas fuera de rango")

    punto = ee.Geometry.Point([lon, lat])

    # ------------------------
    # CONSULTAS (2 en total)
    # ------------------------
    try:
        suelo = SUELO.reduceRegion(reducer=ee.Reducer.first(), geometry=punto, scale=250).getInfo()
        relieve = RELIEVE.reduceRegion(reducer=ee.Reducer.first(), geometry=punto, scale=30).getInfo()
    except ee.EEException as e:
        raise HTTPException(status_code=502, detail=f"Error de Earth Engine: {e}")

    # Si el punto cae en el mar, en un cuerpo de agua o fuera del mapa, no hay datos
    necesarios = ["ph", "humedad", "arcilla", "arena", "carbono"]
    if any(suelo.get(c) is None for c in necesarios):
        raise HTTPException(
            status_code=404,
            detail="No hay datos de suelo en este punto (¿mar, cuerpo de agua o zona urbana?)",
        )

    # ------------------------
    # CAPA SUPERFICIAL (conversión de unidades)
    # ------------------------
    ph_valor = suelo["ph"] / 10  # El dataset guarda pH x 10

    humedad_valor = suelo["humedad"]  # % de agua a 33 kPa (capacidad de campo)

    arcilla_valor = suelo["arcilla"]  # %
    arena_valor = suelo["arena"]      # %
    limo_valor = max(0.0, 100 - arcilla_valor - arena_valor)

    # Carbono orgánico: el dataset lo guarda en unidades de "x 5 g/kg".
    #   g/kg = valor * 5     ->     % = g/kg / 10
    # Materia orgánica = carbono orgánico (%) x 1.724 (factor de Van Bemmelen)
    carbono_porcentaje = suelo["carbono"] * 5 / 10
    materia_organica = carbono_porcentaje * 1.724

    elevacion = relieve.get("elevation")
    pendiente = relieve.get("pendiente")

    # ------------------------
    # CLASIFICACIONES
    # ------------------------
    if ph_valor < 5.5:
        estado_ph = "Muy ácido"
    elif ph_valor < 6.5:
        estado_ph = "Ácido"
    elif ph_valor <= 7.5:
        estado_ph = "Neutro"
    else:
        estado_ph = "Alcalino"

    if materia_organica < 1:
        estado_mo = "Muy baja"
    elif materia_organica < 2:
        estado_mo = "Baja"
    elif materia_organica < 4:
        estado_mo = "Media"
    elif materia_organica < 6:
        estado_mo = "Alta"
    else:
        estado_mo = "Muy alta"

    # ------------------------
    # RESPUESTA (mismos nombres que espera la app)
    # ------------------------
    return {
        "latitud": lat,
        "longitud": lon,

        "ph": round(ph_valor, 2),
        "estado_ph": estado_ph,

        "humedad": round(humedad_valor, 2),

        "arcilla": round(arcilla_valor, 2),
        "arena": round(arena_valor, 2),
        "limo": round(limo_valor, 2),

        "materia_organica": round(materia_organica, 2),
        "estado_materia_organica": estado_mo,

        "elevacion": round(elevacion, 2) if elevacion is not None else None,
        "pendiente": round(pendiente, 2) if pendiente is not None else None,
    }


if __name__ == "__main__":
    import uvicorn

    print("API de suelo en http://localhost:8000")
    uvicorn.run(app, host="0.0.0.0", port=8000)
