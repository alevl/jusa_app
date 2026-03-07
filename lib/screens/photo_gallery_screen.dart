import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:url_launcher/url_launcher.dart';

class PhotoGalleryScreen extends StatefulWidget {
  final List<dynamic>? fotosServidor;
  final dynamic asignacion;
  final int nivelId;

  static const String baseImageUrl =
      "https://sistema.jusaimpulsemkt.com/storage/";

  const PhotoGalleryScreen({
    super.key,
    required this.fotosServidor,
    required this.asignacion,
    required this.nivelId,
  });

  @override
  State<PhotoGalleryScreen> createState() => _PhotoGalleryScreenState();
}

class _PhotoGalleryScreenState extends State<PhotoGalleryScreen> {
  late List<dynamic> fotos;
  final Map<String, int> _tiemposFotos = {};
  bool _cargandoTiempos = true;
  bool _actualizando = false;
  String _direccionEscrita = "Cargando dirección...";

  final Completer<GoogleMapController> _controller =
      Completer<GoogleMapController>();
  late LatLng _ubicacionInicial;
  final Set<Marker> _markers = {};

  final String _googleMapsApiKey = "TU_API_KEY_AQUI";

  @override
  void initState() {
    super.initState();
    fotos =
        widget.fotosServidor != null ? List.from(widget.fotosServidor!) : [];
    _inicializarPantalla();
  }

  void _inicializarPantalla() {
    try {
      _procesarFotosIniciales();
      _inicializarPersistencia();
    } catch (e) {
      debugPrint("Error en inicialización: $e");
      if (mounted) {
        setState(() {
          _cargandoTiempos = false;
        });
      }
    }
  }

  void _procesarFotosIniciales() {
    try {
      if (fotos.isNotEmpty) {
        fotos.sort((a, b) {
          int idA = int.tryParse(a['id']?.toString() ?? '0') ?? 0;
          int idB = int.tryParse(b['id']?.toString() ?? '0') ?? 0;
          return idB.compareTo(idA);
        });
      }

      double lat = double.tryParse(fotos.isNotEmpty
              ? fotos[0]["latitud"]?.toString() ?? '0'
              : widget.asignacion?["latitud"]?.toString() ?? '0') ??
          0.0;
      double lng = double.tryParse(fotos.isNotEmpty
              ? fotos[0]["longitud"]?.toString() ?? '0'
              : widget.asignacion?["longitud"]?.toString() ?? '0') ??
          0.0;

      _ubicacionInicial = LatLng(lat, lng);

      _markers.clear();
      _markers.add(
        Marker(
          markerId: const MarkerId('punto_visita'),
          position: _ubicacionInicial,
          infoWindow: InfoWindow(
            title:
                widget.asignacion?["cliente"]?.toString() ?? "Punto de Visita",
            onTap: () {
              _abrirEnGoogleMaps(lat, lng);
            },
          ),
        ),
      );
      _obtenerDireccionEscrita(lat.toString(), lng.toString());
    } catch (e) {
      _ubicacionInicial = const LatLng(0, 0);
      debugPrint("Error procesando coordenadas: $e");
    }
  }

  Future<void> _refrescarGaleria() async {
    if (_actualizando) {
      return;
    }
    setState(() {
      _actualizando = true;
    });

    try {
      final idAsig = widget.asignacion?["id"];
      if (idAsig == null) {
        return;
      }

      final url = Uri.parse(
          "https://sistema.jusaimpulsemkt.com/api/asignaciones-fotos-app/$idAsig");
      final response = await http.get(url).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final List<dynamic> nuevasFotos = json.decode(response.body);
        if (mounted) {
          setState(() {
            fotos = nuevasFotos;
            _procesarFotosIniciales();
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text("❌ No se pudo conectar con el servidor")),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _actualizando = false;
        });
      }
    }
  }

  Future<void> _obtenerDireccionEscrita(String lat, String lng) async {
    if (lat == "0" || lat == "0.0") {
      return;
    }

    try {
      final url = Uri.parse(
          "https://maps.googleapis.com/maps/api/geocode/json?latlng=$lat,$lng&key=$_googleMapsApiKey&region=ve");
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data["results"] != null && data["results"].isNotEmpty && mounted) {
          setState(() {
            _direccionEscrita = data["results"][0]["formatted_address"];
          });
        }
      }
    } catch (e) {
      debugPrint("Error Geocoding: $e");
    }
  }

  Future<void> _inicializarPersistencia() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ahora = DateTime.now().millisecondsSinceEpoch;

      for (var foto in fotos) {
        String id = foto['id']?.toString() ?? '';
        if (id.isEmpty) {
          continue;
        }
        String key = "timestamp_foto_$id";
        if (!prefs.containsKey(key)) {
          await prefs.setInt(key, ahora);
        }
        _tiemposFotos[id] = prefs.getInt(key) ?? ahora;
      }
    } catch (e) {
      debugPrint("Error SharedPreferences: $e");
    }
    if (mounted) {
      setState(() {
        _cargandoTiempos = false;
      });
    }
  }

  Future<void> _abrirEnGoogleMaps(double lat, double lng) async {
    if (lat == 0.0) {
      return;
    }
    final Uri googleUrl =
        Uri.parse("https://www.google.com/maps/search/?api=1&query=$lat,$lng");
    final Uri appleUrl = Uri.parse("https://maps.apple.com/?q=$lat,$lng");

    try {
      if (Platform.isIOS) {
        if (await canLaunchUrl(appleUrl)) {
          await launchUrl(appleUrl, mode: LaunchMode.externalApplication);
        }
      } else {
        if (await canLaunchUrl(googleUrl)) {
          await launchUrl(googleUrl, mode: LaunchMode.externalApplication);
        }
      }
    } catch (e) {
      debugPrint("Error abriendo mapas: $e");
    }
  }

  bool _puedeEliminar(dynamic foto) {
    try {
      if (widget.nivelId != 3 || _cargandoTiempos) {
        return false;
      }
      String id = foto['id']?.toString() ?? '';
      int? registro = _tiemposFotos[id];
      if (registro == null) {
        return false;
      }

      final String? fechaRaw =
          foto["fecha"]?.toString() ?? foto["created_at"]?.toString();
      if (fechaRaw == null) {
        return false;
      }

      List<String> partes = fechaRaw.split(RegExp(r'[/-]'));
      if (partes.length == 3) {
        DateTime ahora = DateTime.now();
        int dia = int.parse(partes[0]);
        int mes = int.parse(partes[1]);
        int anio = int.parse(partes[2]);
        if (anio != ahora.year || mes != ahora.month || dia != ahora.day) {
          return false;
        }
        return (ahora.millisecondsSinceEpoch - registro) < 300000;
      }
    } catch (e) {
      return false;
    }
    return false;
  }

  Future<void> _eliminarFoto(int id, int index) async {
    try {
      final url = Uri.parse(
          "https://sistema.jusaimpulsemkt.com/api/eliminar-foto-app/$id");
      final response = await http.delete(url);

      if (response.statusCode == 200 && mounted) {
        setState(() {
          fotos.removeAt(index);
        });
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text("✅ Foto eliminada")));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text("❌ Error de red")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool esAuditoria = (widget.nivelId == 2 || widget.nivelId == 4);
    String? iconUrl;
    if (widget.nivelId == 2) {
      iconUrl =
          "https://sistema.jusaimpulsemkt.com/api/asignaciones-supervisor-app/4";
    }
    if (widget.nivelId == 4) {
      iconUrl =
          "https://sistema.jusaimpulsemkt.com/api/asignaciones-cliente-app/4";
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Detalle de Visita",
            style: TextStyle(fontSize: 18, color: Colors.white)),
        backgroundColor: const Color(0xFF424949),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: _actualizando
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.refresh),
            onPressed: _refrescarGaleria,
          ),
          if (iconUrl != null)
            Padding(
              padding: const EdgeInsets.only(right: 12.0),
              child: Image.network(
                iconUrl,
                width: 32,
                height: 32,
                errorBuilder: (context, error, stackTrace) {
                  return const Icon(Icons.account_circle, color: Colors.white);
                },
              ),
            ),
        ],
      ),
      body: _cargandoTiempos
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(
              physics: const ClampingScrollPhysics(),
              slivers: [
                if (esAuditoria)
                  SliverToBoxAdapter(child: _buildMapaInteractivoHeader()),
                if (fotos.isEmpty)
                  const SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(child: Text("NO HAY FOTOS")))
                else
                  SliverPadding(
                    padding: const EdgeInsets.all(12),
                    sliver: _buildGridSliver(),
                  ),
              ],
            ),
    );
  }

  Widget _buildMapaInteractivoHeader() {
    Color rolColor = widget.nivelId == 2 ? Colors.orange : Colors.blue;
    String rolTexto =
        widget.nivelId == 2 ? "VISTA SUPERVISOR" : "VISTA CLIENTE";
    String responsable =
        widget.asignacion?["usuario"]?.toString() ?? "No identificado";

    bool soportaMapa = Platform.isAndroid || Platform.isIOS;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (soportaMapa)
          SizedBox(
            height: 300,
            child: GoogleMap(
              initialCameraPosition:
                  CameraPosition(target: _ubicacionInicial, zoom: 16.0),
              markers: _markers,
              onMapCreated: (controller) {
                if (!_controller.isCompleted) {
                  _controller.complete(controller);
                }
              },
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  // ⚡️ CAMBIO AQUÍ: withValues en lugar de withOpacity
                  color: rolColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: rolColor.withValues(alpha: 0.5)),
                ),
                child: Text(rolTexto,
                    style: TextStyle(
                        color: rolColor,
                        fontSize: 10,
                        fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 16),
              _headerRow(Icons.person, "Responsable: $responsable", bold: true),
              _headerRow(Icons.location_on, _direccionEscrita,
                  color: Colors.redAccent),
              const Divider(height: 30),
              _headerRow(Icons.calendar_today,
                  "Fecha: ${widget.asignacion?["fecha"]?.toString() ?? ''}"),
            ],
          ),
        ),
      ],
    );
  }

  Widget _headerRow(IconData icon, String text,
      {Color? color, bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color ?? Colors.grey[700]),
          const SizedBox(width: 10),
          Expanded(
              child: Text(text,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: bold ? FontWeight.bold : FontWeight.normal))),
        ],
      ),
    );
  }

  Widget _buildGridSliver() {
    return SliverGrid(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 0.8,
      ),
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final f = fotos[index];
          final String fotoPath = f["foto"]?.toString() ?? "";
          final String imageUrl = "${PhotoGalleryScreen.baseImageUrl}$fotoPath";

          return Card(
            clipBehavior: Clip.antiAlias,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Stack(
              children: [
                Positioned.fill(
                  child: Image.network(
                    imageUrl,
                    fit: BoxFit.cover,
                    cacheWidth: 400,
                    errorBuilder: (c, e, s) {
                      return const Center(
                          child: Icon(Icons.broken_image, color: Colors.grey));
                    },
                    loadingBuilder: (c, child, progress) {
                      if (progress == null) {
                        return child;
                      }
                      return const Center(
                          child: CircularProgressIndicator(strokeWidth: 2));
                    },
                  ),
                ),
                if (_puedeEliminar(f))
                  Positioned(
                    top: 5,
                    right: 5,
                    child: CircleAvatar(
                      backgroundColor: Colors.white,
                      radius: 18,
                      child: IconButton(
                        icon: const Icon(Icons.delete,
                            color: Colors.red, size: 18),
                        onPressed: () {
                          _confirmarEliminacion(
                              int.parse(f["id"].toString()), index);
                        },
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
        childCount: fotos.length,
      ),
    );
  }

  void _confirmarEliminacion(int id, int index) {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text("¿Eliminar foto?"),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
              },
              child: const Text("NO"),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _eliminarFoto(id, index);
              },
              child: const Text("SÍ"),
            ),
          ],
        );
      },
    );
  }
}
