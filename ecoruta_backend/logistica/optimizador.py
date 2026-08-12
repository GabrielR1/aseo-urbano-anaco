"""
Módulo Optimizador de Rutas Ecológicas y Cálculo de Huella de Carbono (CO2)
Proyecto EcoRuta
"""

FACTOR_EMISION_CO2_DIESEL = 0.264  # kg de CO2 emitidos por kilómetro promedio en camiones de recolección

def calcular_eficiencia_ecologica(distancia_km, rendimiento_km_l=5.0, capacidad_toneladas=10.0):
    """
    Calcula los litros estimados de combustible, el costo aproximado y la huella de CO2.
    """
    distancia_float = float(distancia_km or 10.0)
    rendimiento_float = float(rendimiento_km_l or 5.0)
    if rendimiento_float <= 0:
        rendimiento_float = 5.0

    litros_estimados = round(distancia_float / rendimiento_float, 2)
    costo_estimado_usd = round(litros_estimados * 0.50, 2)  # Precio ref: $0.50 por litro
    emision_co2_kg = round(distancia_float * FACTOR_EMISION_CO2_DIESEL, 2)
    co2_ahorrado_estimado_kg = round(emision_co2_kg * 0.15, 2)  # 15% de ahorro con optimización de trayectoria

    return {
        'distancia_km': distancia_float,
        'rendimiento_km_l': rendimiento_float,
        'capacidad_toneladas': float(capacidad_toneladas),
        'litros_estimados': litros_estimados,
        'costo_estimado_usd': costo_estimado_usd,
        'emision_co2_kg': emision_co2_kg,
        'co2_ahorrado_estimado_kg': co2_ahorrado_estimado_kg,
        'eficiencia_calificacion': 'A+' if rendimiento_float >= 5.5 else ('A' if rendimiento_float >= 4.5 else 'B')
    }
