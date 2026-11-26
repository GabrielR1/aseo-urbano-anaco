"""
Módulo de Gamificación, Evaluación de Desempeño e Incentivos a Conductores
Proyecto EcoRuta
"""
from django.db.models import Prefetch

from administracion.models import Chofer, PuntajeChofer, IncentivoChofer
from logistica.models import Jornada, PuntoGeolocalizacion

def evaluar_y_actualizar_puntaje_chofer(chofer):
    """
    Calcula de forma automática los kilómetros recorridos, las jornadas finalizadas a tiempo
    y asigna puntos, niveles e insignias de reconocimiento al conductor.
    """
    puntaje, created = PuntajeChofer.objects.get_or_create(chofer=chofer)

    jornadas_finalizadas = list(
        Jornada.objects.filter(chofer=chofer, estado='finalizada').prefetch_related(
            Prefetch(
                'puntos',
                queryset=PuntoGeolocalizacion.objects.order_by('timestamp', 'id'),
            )
        )
    )

    total_jornadas = len(jornadas_finalizadas)
    total_km = sum(j.calcular_distancia_real_km() for j in jornadas_finalizadas)
    
    # Cálculo de puntos: 10 pts por km + 50 pts por jornada finalizada
    puntos_calculados = int((total_km * 10) + (total_jornadas * 50))
    
    # Asignación de Niveles
    if puntos_calculados >= 1000:
        nivel = 'oro'
    elif puntos_calculados >= 400:
        nivel = 'plata'
    else:
        nivel = 'bronce'

    puntaje.puntos_totales = puntos_calculados
    puntaje.km_recorridos_totales = round(total_km, 2)
    puntaje.jornadas_exitosas = total_jornadas
    puntaje.nivel = nivel
    puntaje.save()

    # Otorgar insignias automáticas según metas logradas
    if total_jornadas >= 1 and not IncentivoChofer.objects.filter(chofer=chofer, tipo_insignia='eco').exists():
        IncentivoChofer.objects.create(
            chofer=chofer,
            titulo="🌿 Primera Ruta Ecológica Finalizada",
            descripcion="Felicidades por completar con éxito tu primera jornada de recolección sustentable.",
            tipo_insignia="eco",
            monto_bono_usd=10.0
        )

    if total_km >= 100 and not IncentivoChofer.objects.filter(chofer=chofer, tipo_insignia='maestro').exists():
        IncentivoChofer.objects.create(
            chofer=chofer,
            titulo="🚚 Maestro del Volante (100+ Km)",
            descripcion="Has alcanzado más de 100 kilómetros de recorrido limpio supervisado.",
            tipo_insignia="maestro",
            monto_bono_usd=25.0
        )

    if puntos_calculados >= 500 and not IncentivoChofer.objects.filter(chofer=chofer, tipo_insignia='estrella').exists():
        IncentivoChofer.objects.create(
            chofer=chofer,
            titulo="🥇 Chofer Estrella EcoRuta",
            descripcion="Reconocimiento por alto nivel de eficiencia ecológica y constancia operativa.",
            tipo_insignia="estrella",
            monto_bono_usd=50.0
        )

    return puntaje
