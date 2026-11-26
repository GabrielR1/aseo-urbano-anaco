"""Funciones compartidas para serializar la telemetría de jornadas.

Centraliza la lógica que antes estaba duplicada entre la vista del mapa web
(``dashboard.views.mapa_monitoreo``) y el endpoint de la API
(``logistica.views.monitoreo_en_vivo``).
"""

from django.utils import timezone

MAX_PUNTOS_TRAYECTORIA = 120


def puntos_ordenados(jornada):
    """Devuelve los puntos GPS en orden cronológico usando el prefetch si existe."""
    cache = getattr(jornada, "_prefetched_objects_cache", {}) or {}
    if "puntos" in cache:
        return list(cache["puntos"])
    return list(jornada.puntos.order_by("timestamp", "id"))


def serializar_camion(jornada, max_trayectoria=MAX_PUNTOS_TRAYECTORIA):
    """Construye el diccionario de telemetría de una jornada."""
    puntos = puntos_ordenados(jornada)
    visibles = puntos[-max_trayectoria:] if max_trayectoria else puntos
    ultimo = visibles[-1] if visibles else None

    return {
        "jornada_id": jornada.id,
        "vehiculo": f"{jornada.vehiculo.marca} {jornada.vehiculo.modelo} ({jornada.vehiculo.placa})",
        "modelo": f"{jornada.vehiculo.marca} {jornada.vehiculo.modelo}",
        "placa": jornada.vehiculo.placa,
        "ruta": jornada.ruta.nombre,
        "zona": jornada.ruta.zona or "Municipio Anaco",
        "chofer": jornada.chofer.usuario.get_full_name() or jornada.chofer.usuario.username,
        "estado": jornada.estado,
        "estado_display": jornada.get_estado_display(),
        "tiene_gps": ultimo is not None,
        "latitud": float(ultimo.latitud) if ultimo else None,
        "longitud": float(ultimo.longitud) if ultimo else None,
        "velocidad_kmh": round(float(ultimo.velocidad_kmh or 0.0), 1) if ultimo else 0.0,
        "precision_metros": (
            round(float(ultimo.precision_metros), 1)
            if (ultimo and ultimo.precision_metros is not None)
            else None
        ),
        "distancia_real_km": jornada.calcular_distancia_real_km(puntos=puntos),
        "puntos_count": len(puntos),
        "trayectoria": [[float(p.latitud), float(p.longitud)] for p in visibles],
        "ultima_actualizacion": (
            timezone.localtime(ultimo.timestamp).strftime("%H:%M:%S") if ultimo else None
        ),
    }


def serializar_incidencia(incidencia, incluir_foto=True):
    """Construye el diccionario de una incidencia para las interfaces de monitoreo."""
    return {
        "id": incidencia.id,
        "jornada_id": incidencia.jornada_id,
        "vehiculo_placa": (
            incidencia.jornada.vehiculo.placa
            if incidencia.jornada and incidencia.jornada.vehiculo
            else "S/V"
        ),
        "descripcion": incidencia.descripcion,
        "latitud": float(incidencia.latitud) if incidencia.latitud is not None else None,
        "longitud": float(incidencia.longitud) if incidencia.longitud is not None else None,
        "estado": incidencia.estado,
        "estado_display": incidencia.get_estado_display(),
        "foto_url": incidencia.foto.url if (incluir_foto and incidencia.foto) else None,
        "resolucion_detalles": incidencia.resolucion_detalles,
        "timestamp": timezone.localtime(incidencia.timestamp).strftime("%d/%m/%Y %H:%M"),
    }
