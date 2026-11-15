"""
Simulación Monte Carlo de rotaciones de cultivo con el clima REAL de la parcela.

Necesita, en la MISMA carpeta:
    - montecarlo.py
    - BDPLANS_cultivos.csv            (datos botánicos)
    - clima_2025_diario.csv           (lo genera API_AÑO_MONTECARLO.py)

Uso:
    python simular_rotacion.py

Ajusta los datos de tu parcela en la sección CONFIGURACIÓN.
"""

import csv
import time
from datetime import datetime
from pathlib import Path

import montecarlo as mc

# ============================================================
# CONFIGURACIÓN (datos de tu parcela)
# ============================================================
ARCHIVO_CLIMA = "clima_2025_diario.csv"
ARCHIVO_CULTIVOS = "BDPLANS_cultivos.csv"

# Suelo de la parcela (valores de tu API de suelo / Earth Engine)
PH_SUELO = 7.3            # pH
PROFUNDIDAD_SUELO = 1.0   # metros
HUMEDAD_SUELO = 33        # % de agua a capacidad de campo
MATERIA_ORGANICA = 7.76   # %
ARCILLA = 35              # %
ARENA = 38                # %
ELEVACION = 9             # metros
PENDIENTE = 1.36          # grados
SIMULACIONES = 1000       # Futuros posibles por rotación
LARGO_ROTACION = 4        # Cultivos en la rotación (2 a 4)
MES_SIEMBRA = datetime.now().month  # Mes en que empezaría la rotación (1-12)
# ============================================================


def leer_bdplans(ruta):
    """Lee el CSV botánico (separado por ';'), con o sin re-guardado en Excel."""
    for codificacion in ("utf-8-sig", "latin-1"):
        try:
            with open(ruta, encoding=codificacion, newline="") as f:
                return {fila["ID EcoPort"].strip(): fila for fila in csv.DictReader(f, delimiter=";")}
        except UnicodeDecodeError:
            continue
    raise ValueError(f"No se pudo leer {ruta}")


def imprimir_resultado(titulo, r):
    print("\n" + "=" * 78)
    print(titulo)
    print("=" * 78)
    if not r["ranking"]:
        print(r["mensaje"])
        return
    print(r["mensaje"])
    print(f"\nClima usado: {r['fuenteClima']}")
    print(f"Rotaciones probadas: {r['rotacionesEvaluadas']:,}  |  Cultivos considerados: {', '.join(r['cultivosConsiderados'])}\n")

    print(f"{'#':>2}  {'Rotación (variada)':58} {'Éxito':>6} {'Puntaje':>8} {'Meses':>6} {'Riego mm':>9}")
    print("-" * 92)
    for i, fila in enumerate(r["ranking"], start=1):
        rot = " → ".join(fila["rotacion"])
        riego = "—" if fila["riegoNecesarioMm"] is None else f"{fila['riegoNecesarioMm']:.0f}"
        print(f"{i:2d}  {rot:58} {fila['exito'] * 100:5.1f}% {fila['puntaje']:8.2f} {fila['mesesPromedio']:6.1f} {riego:>9}")

    mejor = r["mejor"]
    print("\nÉxito de cada cultivo en la mejor rotación (y calificación de tu suelo para él, 0 a 1):")
    for nombre, exito in zip(mejor["rotacion"], mejor["exitoPorCultivo"]):
        f = mejor["factoresSuelo"][nombre]
        print(f"  - {nombre:20} {exito * 100:5.1f}%   pH {f['ph']:.2f} | textura {f['textura']:.2f} | "
              f"fertilidad {f['fertilidad']:.2f} | altitud {f['altitud']:.2f} | pendiente {f['pendiente']:.2f}")
    if mejor["riegoNecesarioMm"] is not None:
        print(f"Agua que faltaría reponer con riego (promedio): {mejor['riegoNecesarioMm']:.0f} mm "
              f"(= {mejor['riegoNecesarioMm']:.0f} litros por m²)")


if __name__ == "__main__":
    carpeta = Path(__file__).parent
    ruta_clima = carpeta / ARCHIVO_CLIMA
    ruta_cultivos = carpeta / ARCHIVO_CULTIVOS

    if not ruta_clima.exists():
        raise SystemExit(f"No encontré {ARCHIVO_CLIMA}. Primero corre API_AÑO_MONTECARLO.py en esta carpeta.")
    if not ruta_cultivos.exists():
        raise SystemExit(f"No encontré {ARCHIVO_CULTIVOS} en esta carpeta.")

    clima = mc.cargar_clima_diario(ruta_clima)
    cultivos = mc.cargar_candidatos(leer_bdplans(ruta_cultivos))

    resumen = mc.resumen_clima_diario(clima)
    meses = ["Ene", "Feb", "Mar", "Abr", "May", "Jun", "Jul", "Ago", "Sep", "Oct", "Nov", "Dic"]
    print("Clima real de la parcela (promedio por mes):")
    print("  " + "  ".join(f"{m:>5}" for m in meses))
    print("T°C" + "".join(f"{t:7.1f}" for t in resumen["temperatura"]))
    print("Lluv" + "".join(f"{l:7.0f}" for l in resumen["lluvia"]) + "  (mm/mes)")
    print("ET " + "".join(f"{e:7.0f}" for e in resumen["evapotranspiracion"]) + "  (mm/mes)")
    print(f"\n{len(cultivos)} cultivos candidatos leídos de {ARCHIVO_CULTIVOS}.")

    suelo = mc.SueloParcela(
        ph=PH_SUELO,
        profundidad=PROFUNDIDAD_SUELO,
        humedad=HUMEDAD_SUELO,
        materia_organica=MATERIA_ORGANICA,
        arcilla=ARCILLA,
        arena=ARENA,
        elevacion=ELEVACION,
        pendiente=PENDIENTE,
    )
    print(f"\nSuelo: textura {suelo.clase_textura}, fertilidad {suelo.fertilidad}, "
          f"agua que guarda el suelo ~{suelo.reserva_agua_mm:.0f} mm")

    for con_riego in (False, True):
        inicio = time.time()
        resultado = mc.simular_rotaciones(
            cultivos,
            mes_inicio=MES_SIEMBRA - 1,
            ph=PH_SUELO,
            profundidad=PROFUNDIDAD_SUELO,
            n_sim=SIMULACIONES,
            largo=LARGO_ROTACION,
            riego=con_riego,
            clima_diario=clima,
            suelo=suelo,
            top=12,
        )
        imprimir_resultado(
            f"RESULTADO {'CON' if con_riego else 'SIN'} RIEGO  ({time.time() - inicio:.1f} s)",
            resultado,
        )
