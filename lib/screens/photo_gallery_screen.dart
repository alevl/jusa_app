import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:url_launcher/url_launcher.dart';

class PhotoGalleryScreen extends StatefulWidget {
  final List<dynamic> fotosServidor;
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

  // 🚨 REEMPLAZA ESTO CON TU CLAVE REAL DE GOOGLE MAPS
  final String _googleMapsApiKey = "TU_API_KEY_AQUI";

  @override
  void initState() {
    super.initState();
    fotos = List.from(widget.fotosServidor);
    _procesarFotosIniciales();
    _inicializarPersistencia();
  }

  void _procesarFotosIniciales() {
    fotos.sort((a, b) => (b['id'] ?? 0).compareTo(a['id'] ?? 0));

    double lat = double.tryParse(fotos.isNotEmpty
            ? fotos[0]["latitud"].toString()
            : widget.asignacion["latitud"].toString()) ??
        0.0;
    double lng = double.tryParse(fotos.isNotEmpty
            ? fotos[0]["longitud"].toString()
            : widget.asignacion["longitud"].toString()) ??
        0.0;

    _ubicacionInicial = LatLng(lat, lng);

    _markers.clear();
    _markers.add(
      Marker(
        markerId: const MarkerId('punto_visita'),
        position: _ubicacionInicial,
        infoWindow: InfoWindow(
          title: widget.asignacion["cliente"] ?? "Punto de Visita",
          snippet: "Toca para abrir en GPS",
          onTap: () {
            _abrirEnGoogleMaps(lat, lng);
          },
        ),
      ),
    );
    _obtenerDireccionEscrita(lat.toString(), lng.toString());
  }

  Future<void> _refrescarGaleria() async {
    if (_actualizando) {
      return;
    }

    setState(() {
      _actualizando = true;
    });

    try {
      final idAsig = widget.asignacion["id"];
      final url = Uri.parse(
          "https://sistema.jusaimpulsemkt.com/api/asignaciones-fotos-app/$idAsig");

      final response = await http.get(url);
      if (response.statusCode == 200) {
        final List<dynamic> nuevasFotos = json.decode(response.body);
        setState(() {
          fotos = nuevasFotos;
          _procesarFotosIniciales();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("❌ Error al actualizar la galería")),
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
    if (lat == "0" || lng == "0" || lat == "0.0") {
      if (mounted) {
        setState(() {
          _direccionEscrita = "Ubicación no disponible";
        });
      }
      return;
    }

    final url = Uri.parse(
        "https://maps.googleapis.com/maps/api/geocode/json?latlng=$lat,$lng&key=$_googleMapsApiKey&region=ve");

    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data["results"].isNotEmpty && mounted) {
          setState(() {
            _direccionEscrita = data["results"][0]["formatted_address"];
          });
        }
      }
    } catch (e) {
      debugPrint("Error geocoding: $e");
    }
  }

  Future<void> _inicializarPersistencia() async {
    final prefs = await SharedPreferences.getInstance();
    final ahora = DateTime.now().millisecondsSinceEpoch;

    for (var foto in fotos) {
      String id = foto['id'].toString();
      String key = "timestamp_foto_$id";
      if (!prefs.containsKey(key)) {
        await prefs.setInt(key, ahora);
      }
      _tiemposFotos[id] = prefs.getInt(key) ?? ahora;
    }

    if (mounted) {
      setState(() {
        _cargandoTiempos = false;
      });
    }
  }

  Future<void> _abrirEnGoogleMaps(double lat, double lng) async {
    if (lat == 0.0 || lng == 0.0) {
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
      debugPrint("Error: $e");
    }
  }

  bool _puedeEliminar(dynamic foto) {
    if (widget.nivelId != 3 || _cargandoTiempos) {
      return false;
    }

    String id = foto['id'].toString();
    int? registro = _tiemposFotos[id];
    if (registro == null) {
      return false;
    }

    final String? fechaRaw = foto["fecha"] ?? foto["created_at"];
    if (fechaRaw == null) {
      return false;
    }

    try {
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

  Future<void> eliminarFoto(int id, int index) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final url = Uri.parse(
          "https://sistema.jusaimpulsemkt.com/api/eliminar-foto-app/$id");
      final response = await http.delete(url);

      if (response.statusCode == 200 && mounted) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove("timestamp_foto_$id");
        setState(() {
          fotos.removeAt(index);
        });
        messenger
            .showSnackBar(const SnackBar(content: Text("✅ Foto eliminada")));
      }
    } catch (e) {
      if (mounted) {
        messenger
            .showSnackBar(const SnackBar(content: Text("❌ Error de conexión")));
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
    } else if (widget.nivelId == 4) {
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
            tooltip: "Actualizar fotos",
          ),
          if (iconUrl != null)
            Padding(
              padding: const EdgeInsets.only(right: 12.0),
              child: Image.network(iconUrl, width: 32, height: 32,
                  errorBuilder: (context, error, stackTrace) {
                return const Icon(Icons.account_circle, color: Colors.white);
              }),
            ),
        ],
      ),
      body: _cargandoTiempos
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(
              slivers: [
                if (esAuditoria)
                  SliverToBoxAdapter(child: _buildMapaInteractivoHeader()),
                if (fotos.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _buildEmptyState(),
                  )
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
    String responsableNombre =
        widget.asignacion["usuario"] ?? "No identificado";

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 300,
          width: double.infinity,
          decoration: BoxDecoration(
              border: Border(
                  bottom: BorderSide(color: Colors.grey[300]!, width: 1))),
          child: GoogleMap(
            mapType: MapType.normal,
            initialCameraPosition:
                CameraPosition(target: _ubicacionInicial, zoom: 17.5),
            markers: _markers,
            zoomControlsEnabled: true,
            myLocationButtonEnabled: false,
            onMapCreated: (GoogleMapController controller) {
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
                  // ✅ USO DE WITHVALUES PARA EVITAR DEPRECACIÓN
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
              _headerRow(Icons.person_pin_circle_rounded,
                  "Responsable: $responsableNombre",
                  bold: true),
              _headerRow(Icons.pin_drop_rounded, _direccionEscrita,
                  color: Colors.redAccent),
              const Divider(height: 30),
              _headerRow(Icons.calendar_today_rounded,
                  "Fecha: ${widget.asignacion["fecha"]}"),
              _headerRow(Icons.access_time_rounded,
                  "Hora: ${widget.asignacion["hora"] ?? 'N/A'}"),
            ],
          ),
        ),
        const Divider(thickness: 1, height: 1),
      ],
    );
  }

  Widget _headerRow(IconData icon, String text,
      {Color? color, bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color ?? Colors.grey[700]),
          const SizedBox(width: 12),
          Expanded(
              child: Text(text,
                  style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[800],
                      height: 1.3,
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
        childAspectRatio: 0.85,
      ),
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final f = fotos[index];
          final String imageUrl =
              "${PhotoGalleryScreen.baseImageUrl}${f["foto"]}";
          final bool permiteEliminar = _puedeEliminar(f);
          return Card(
            elevation: 2,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Column(
                children: [
                  Expanded(
                    child: Stack(
                      children: [
                        Positioned.fill(
                            child: Image.network(imageUrl, fit: BoxFit.cover,
                                errorBuilder: (c, e, s) {
                          return const Icon(Icons.broken_image);
                        })),
                        if (permiteEliminar)
                          Positioned(
                              right: 5,
                              top: 5,
                              child: GestureDetector(
                                  onTap: () {
                                    _confirmarEliminacion(f["id"], index);
                                  },
                                  child: Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: const BoxDecoration(
                                          color: Colors.white,
                                          shape: BoxShape.circle),
                                      child: const Icon(Icons.delete_forever,
                                          color: Colors.red, size: 20)))),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text(f["fecha"] ?? "",
                        style: const TextStyle(fontSize: 10)),
                  )
                ],
              ),
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
        builder: (ctx) => AlertDialog(
                title: const Text("¿Eliminar foto?"),
                content: const Text("Esta acción no se puede deshacer."),
                actions: [
                  TextButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                      },
                      child: const Text("CANCELAR")),
                  TextButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        eliminarFoto(id, index);
                      },
                      child: const Text("SÍ, ELIMINAR",
                          style: TextStyle(color: Colors.red))),
                ]));
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.photo_library_outlined, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 15),
          const Text("NO HAY FOTOS REGISTRADAS",
              style: TextStyle(
                  color: Color(0xFF9E9E9E), fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
