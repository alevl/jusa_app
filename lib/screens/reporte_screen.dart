import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'photo_gallery_screen.dart';

class ReporteScreen extends StatefulWidget {
  final int nivelId;
  final String usuarioNombre;

  const ReporteScreen({
    super.key,
    required this.nivelId,
    required this.usuarioNombre,
  });

  @override
  State<ReporteScreen> createState() => _ReporteScreenState();
}

class _ReporteScreenState extends State<ReporteScreen> {
  List<dynamic> _asignaciones = [];
  List<dynamic> _asignacionesFiltradas = [];
  bool _cargando = true;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _obtenerDatos();
  }

  Future<void> _obtenerDatos() async {
    try {
      final url = Uri.parse(
          "https://sistema.jusaimpulsemkt.com/api/asignaciones-cliente-app/4");
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (mounted) {
          setState(() {
            _asignaciones = data is List ? data : (data['datos'] ?? []);
            _asignacionesFiltradas = _asignaciones;
            _cargando = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _cargando = false;
        });
      }
    }
  }

  void _filtrarBusqueda(String query) {
    setState(() {
      _asignacionesFiltradas = _asignaciones.where((a) {
        final String cliente = a['cliente']?.toString().toLowerCase() ?? "";
        final String plaza = a['plaza']?.toString().toLowerCase() ?? "";
        return cliente.contains(query.toLowerCase()) ||
            plaza.contains(query.toLowerCase());
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          "Reporte Fotográfico",
          style: TextStyle(
              color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF424949),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Column(
        children: [
          _buildHeader(),
          _buildSearchBar(),
          Expanded(
            child: _cargando
                ? const Center(child: CircularProgressIndicator())
                : _buildListaReportes(),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20),
      width: double.infinity,
      child: Column(
        children: [
          Image.network(
            "https://sistema.jusaimpulsemkt.com/api/asignaciones-cliente-app/4",
            height: 60,
            errorBuilder: (context, error, stackTrace) {
              return const Icon(Icons.business,
                  size: 60, color: Colors.blueGrey);
            },
          ),
          const SizedBox(height: 10),
          Text(
            "Bienvenido: ${widget.usuarioNombre}",
            style: const TextStyle(
                color: Color(0xFF5D6D7E), fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
      child: TextField(
        controller: _searchController,
        onChanged: _filtrarBusqueda,
        decoration: InputDecoration(
          hintText: "Buscar por cliente o plaza...",
          prefixIcon: const Icon(Icons.search),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          contentPadding: const EdgeInsets.symmetric(vertical: 0),
        ),
      ),
    );
  }

  Widget _buildListaReportes() {
    if (_asignacionesFiltradas.isEmpty) {
      return const Center(child: Text("No se encontraron registros"));
    }

    return ListView.builder(
      itemCount: _asignacionesFiltradas.length,
      itemBuilder: (context, index) {
        final a = _asignacionesFiltradas[index];

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
          elevation: 3,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _filaInformacion("Fecha:", a['fecha']),
                      const SizedBox(height: 4),
                      _filaInformacion("Hora:", a['hora'] ?? 'S/H'),
                      const SizedBox(height: 4),
                      _filaInformacion("Cliente:", a['cliente']),
                      const SizedBox(height: 4),
                      _filaInformacion("Plaza:", a['plaza'] ?? a['sucursal']),
                      const SizedBox(height: 4),
                      _filaInformacion("Ubicación:",
                          a['municipio'] ?? a['ubicacion'] ?? 'S/D'),
                      const SizedBox(height: 4),
                      _filaInformacion("Estatus:", a['estatus'],
                          esEstatus: true),
                    ],
                  ),
                ),
                InkWell(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => PhotoGalleryScreen(
                          fotosServidor: a['fotos'] ?? [],
                          asignacion: a,
                          nivelId: widget.nivelId,
                        ),
                      ),
                    );
                  },
                  child: Image.network(
                    "https://sistema.jusaimpulsemkt.com/api/asignaciones-cliente-app/4",
                    width: 30,
                    height: 30,
                    errorBuilder: (c, e, s) {
                      return const Icon(Icons.image,
                          color: Colors.blue, size: 30);
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _filaInformacion(String etiqueta, dynamic valor,
      {bool esEstatus = false}) {
    return RichText(
      text: TextSpan(
        style: const TextStyle(
            color: Colors.black, fontSize: 13, fontFamily: 'Roboto'),
        children: [
          TextSpan(
              text: "$etiqueta ",
              style: const TextStyle(fontWeight: FontWeight.bold)),
          TextSpan(
            text: "${valor ?? 'N/A'}",
            style: TextStyle(
              fontWeight: esEstatus ? FontWeight.bold : FontWeight.normal,
              color: esEstatus ? Colors.blueGrey : Colors.black,
            ),
          ),
        ],
      ),
    );
  }
}
