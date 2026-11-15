from fastapi import FastAPI
import ee

# CONFIGURAR EARTH ENGINE
SERVICE_ACCOUNT = "earth-engine-service@dark-furnace-436804-i6.iam.gserviceaccount.com"

credentials = ee.ServiceAccountCredentials(
    SERVICE_ACCOUNT,
    "credentials.json"
)

ee.Initialize(credentials)

app = FastAPI()


@app.get("/suelo")
def obtener_suelo(lat: float, lon: float):

    punto = ee.Geometry.Point([lon, lat])

    ph = ee.Image(
        'OpenLandMap/SOL/SOL_PH-H2O_USDA-4C1A2A_M/v02'
    )

    humedad = ee.Image(
        'OpenLandMap/SOL/SOL_WATERCONTENT-33KPA_USDA-4B1C_M/v01'
    )

    arcilla = ee.Image(
        'OpenLandMap/SOL/SOL_CLAY-WFRACTION_USDA-3A1A1A_M/v02'
    )

    arena = ee.Image(
        'OpenLandMap/SOL/SOL_SAND-WFRACTION_USDA-3A1A1A_M/v02'
    )

    dem = ee.Image('USGS/SRTMGL1_003')

    pendiente_img = ee.Terrain.slope(dem)

    ph_result = ph.reduceRegion(
        reducer=ee.Reducer.first(),
        geometry=punto,
        scale=250
    ).getInfo()

    humedad_result = humedad.reduceRegion(
        reducer=ee.Reducer.first(),
        geometry=punto,
        scale=250
    ).getInfo()

    arcilla_result = arcilla.reduceRegion(
        reducer=ee.Reducer.first(),
        geometry=punto,
        scale=250
    ).getInfo()

    arena_result = arena.reduceRegion(
        reducer=ee.Reducer.first(),
        geometry=punto,
        scale=250
    ).getInfo()

    elevacion_result = dem.reduceRegion(
        reducer=ee.Reducer.first(),
        geometry=punto,
        scale=30
    ).getInfo()

    pendiente_result = pendiente_img.reduceRegion(
        reducer=ee.Reducer.first(),
        geometry=punto,
        scale=30
    ).getInfo()

    ph_superficial = ph_result["b0"] / 10
    humedad_superficial = humedad_result["b0"]
    arcilla_superficial = arcilla_result["b0"]
    arena_superficial = arena_result["b0"]

    limo = 100 - arcilla_superficial - arena_superficial

    return {
        "ph": ph_superficial,
        "humedad": humedad_superficial,
        "arcilla": arcilla_superficial,
        "arena": arena_superficial,
        "limo": limo,
        "elevacion": elevacion_result["elevation"],
        "pendiente": pendiente_result["slope"]
    }