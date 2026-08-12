from django import forms
from .models import Ruta, Vehiculo

class RutaForm(forms.ModelForm):
    class Meta:
        model = Ruta
        fields = ['nombre', 'descripcion', 'zona', 'distancia_estimada_km']
        widgets = {
            'nombre': forms.TextInput(attrs={
                'class': 'form-input',
                'placeholder': 'Ej. Ruta Casco Histórico',
                'required': True
            }),
            'zona': forms.TextInput(attrs={
                'class': 'form-input',
                'placeholder': 'Ej. Sector Norte',
                'required': True
            }),
            'distancia_estimada_km': forms.NumberInput(attrs={
                'class': 'form-input',
                'step': '0.01',
                'placeholder': 'Ej. 15.5',
                'required': True
            }),
            'descripcion': forms.Textarea(attrs={
                'class': 'form-input',
                'rows': 3,
                'placeholder': 'Descripción del recorrido o puntos clave...'
            }),
        }

class VehiculoForm(forms.ModelForm):
    class Meta:
        model = Vehiculo
        fields = ['placa', 'marca', 'modelo', 'capacidad_toneladas', 'estado', 'rendimiento_km_por_litro']
        widgets = {
            'placa': forms.TextInput(attrs={'class': 'form-input', 'placeholder': 'Ej. A12B34'}),
            'marca': forms.TextInput(attrs={'class': 'form-input', 'placeholder': 'Ej. Chevrolet'}),
            'modelo': forms.TextInput(attrs={'class': 'form-input', 'placeholder': 'Ej. NPR 2022'}),
            'capacidad_toneladas': forms.NumberInput(attrs={'class': 'form-input', 'step': '0.1'}),
            'estado': forms.Select(attrs={'class': 'form-input'}),
            'rendimiento_km_por_litro': forms.NumberInput(attrs={'class': 'form-input', 'step': '0.1'}),
        }
