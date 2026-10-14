pwdimport 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:weather_animation/weather_animation.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ru', null);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Погода',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.blue,
        fontFamily: 'Roboto',
        useMaterial3: true,
      ),
      home: const WeatherScreen(),
    );
  }
}

class WeatherScreen extends StatefulWidget {
  const WeatherScreen({super.key});

  @override
  State<WeatherScreen> createState() => _WeatherScreenState();
}

class _WeatherScreenState extends State<WeatherScreen> {
  bool _isLoading = true;
  String _errorMessage = '';

  String _cityName = 'Загрузка...';
  double _currentTemp = 0;
  double _apparentTemp = 0;
  int _humidity = 0;
  double _windSpeed = 0;
  double _pressure = 0;
  double _uvIndex = 0;
  String _sunrise = '';
  String _sunset = '';
  int _weatherCode = 0;

  List<dynamic> _dailyForecast = [];
  List<Map<String, dynamic>> _hourlyChartData = [];

  @override
  void initState() {
    super.initState();
    _getLocationAndWeather();
  }

  // === 1. GPS + загрузка данных ===
  Future<void> _getLocationAndWeather() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception('Разрешение на геолокацию отклонено');
        }
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.low,
      );

      await _getCityName(position.latitude, position.longitude);
      await _fetchWeather(position.latitude, position.longitude);
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Ошибка: $e. Проверьте разрешения GPS.';
      });
    }
  }

  // === 3. Поиск города вручную ===
  Future<void> _searchCityByName(String cityName) async {
    setState(() {
      _isLoading = true;
      _cityName = 'Поиск...';
      _errorMessage = '';
    });

    try {
      final geoUrl = 'https://geocoding-api.open-meteo.com/v1/search?name=$cityName&count=1&language=ru&format=json';
      final geoResponse = await http.get(Uri.parse(geoUrl));

      if (geoResponse.statusCode == 200) {
        final geoData = json.decode(geoResponse.body);
        if (geoData['results'] != null && geoData['results'].isNotEmpty) {
          final result = geoData['results'][0];
          final lat = result['latitude'];
          final lon = result['longitude'];
          final name = result['name'] ?? cityName;

          setState(() {
            _cityName = name;
          });

          await _fetchWeather(lat, lon);
        } else {
          setState(() {
            _isLoading = false;
            _errorMessage = 'Город "$cityName" не найден';
            _cityName = 'Ошибка';
          });
        }
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Ошибка поиска: $e';
        _cityName = 'Ошибка';
      });
    }
  }

  void _showSearchDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2C3E50),
        title: const Text('Поиск города', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Например: Москва',
            hintStyle: const TextStyle(color: Colors.white54),
            filled: true,
            fillColor: Colors.white10,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) {
              Navigator.pop(context);
              _searchCityByName(value.trim());
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                Navigator.pop(context);
                _searchCityByName(controller.text.trim());
              }
            },
            child: const Text('Найти'),
          ),
        ],
      ),
    );
  }

  Future<void> _getCityName(double lat, double lon) async {
    try {
      final url = 'https://nominatim.openstreetmap.org/reverse?format=json&lat=$lat&lon=$lon&zoom=10&addressdetails=1&accept-language=ru';
      final response = await http.get(Uri.parse(url), headers: {
        'User-Agent': 'FlutterWeatherApp/1.0'
      });

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final address = data['address'];
        String city = address['city'] ?? address['town'] ?? address['village'] ?? address['state'] ?? 'Неизвестно';
        setState(() {
          _cityName = city;
        });
      } else {
        setState(() {
          _cityName = 'Неизвестный город';
        });
      }
    } catch (e) {
      setState(() {
        _cityName = 'Ошибка определения';
      });
    }
  }

  // === 5. Загрузка погоды с UV, восходом, закатом ===
  Future<void> _fetchWeather(double lat, double lon) async {
    try {
      final weatherUrl = 'https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon'
          '&current=temperature_2m,relative_humidity_2m,apparent_temperature,weather_code,wind_speed_10m,surface_pressure'
          '&daily=weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset,uv_index_max'
          '&hourly=temperature_2m,weather_code'
          '&timezone=auto';

      final response = await http.get(Uri.parse(weatherUrl));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        setState(() {
          _currentTemp = data['current']['temperature_2m'];
          _apparentTemp = data['current']['apparent_temperature'];
          _humidity = data['current']['relative_humidity_2m'];
          _windSpeed = data['current']['wind_speed_10m'];
          _pressure = data['current']['surface_pressure'];
          _weatherCode = data['current']['weather_code'];

          _uvIndex = (data['daily']['uv_index_max'][0] ?? 0).toDouble();
          _sunrise = data['daily']['sunrise'][0] ?? '';
          _sunset = data['daily']['sunset'][0] ?? '';

          _dailyForecast = data['daily']['time'].asMap().keys.map((i) {
            return {
              'date': data['daily']['time'][i],
              'max': data['daily']['temperature_2m_max'][i],
              'min': data['daily']['temperature_2m_min'][i],
              'code': data['daily']['weather_code'][i],
              'uv': data['daily']['uv_index_max'][i],
            };
          }).toList();

          List<Map<String, dynamic>> hourlyData = [];
          for (int i = 0; i < 12; i++) {
            hourlyData.add({
              'time': data['hourly']['time'][i],
              'temp': data['hourly']['temperature_2m'][i],
              'code': data['hourly']['weather_code'][i],
            });
          }
          _hourlyChartData = hourlyData;

          _isLoading = false;
        });
      } else {
        throw Exception('Не удалось загрузить погоду');
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Ошибка загрузки данных: $e';
      });
    }
  }

  // === Эмодзи-иконки (вместо Material Icons) ===
  String _getWeatherEmoji(int code) {
    if (code == 0) return '☀️';
    if (code >= 1 && code <= 3) return '⛅';
    if (code >= 45 && code <= 48) return '🌫️';
    if (code >= 51 && code <= 67) return '🌧️';
    if (code >= 71 && code <= 77) return '❄️';
    if (code >= 80 && code <= 82) return '🌦️';
    if (code >= 95) return '⛈️';
    return '☁️';
  }

  String _getUvLevel(double uv) {
    if (uv <= 2) return 'Низкий';
    if (uv <= 5) return 'Умеренный';
    if (uv <= 7) return 'Высокий';
    if (uv <= 10) return 'Очень высокий';
    return 'Экстремальный';
  }

  Color _getUvColor(double uv) {
    if (uv <= 2) return Colors.green;
    if (uv <= 5) return Colors.yellow;
    if (uv <= 7) return Colors.orange;
    if (uv <= 10) return Colors.red;
    return Colors.purple;
  }

  String _formatTime(String iso) {
    if (iso.isEmpty) return '--:--';
    try {
      return DateFormat('HH:mm').format(DateTime.parse(iso));
    } catch (_) {
      return '--:--';
    }
  }

  List<Color> _getBackgroundColors(int code) {
    if (code == 0) return [const Color(0xFF4A90E2), const Color(0xFF2C3E50)];
    if (code >= 1 && code <= 3) return [const Color(0xFF6B7B8C), const Color(0xFF2C3E50)];
    if (code >= 51 && code <= 67) return [const Color(0xFF3A4A5C), const Color(0xFF1A2530)];
    if (code >= 71 && code <= 77) return [const Color(0xFF8FA5B8), const Color(0xFF3A4A5C)];
    if (code >= 95) return [const Color(0xFF2A3A4C), const Color(0xFF0A1520)];
    return [const Color(0xFF4A6B8A), const Color(0xFF2C3E50)];
  }

  // === 1. Фоновые анимации погоды ===
  Widget _buildWeatherEffect(int code) {
    if (code == 0) return const SunWidget();
    if (code >= 1 && code <= 3) return const CloudWidget();
    if (code >= 45 && code <= 48) return const CloudWidget();
    if ((code >= 51 && code <= 67) || (code >= 80 && code <= 82)) return const RainWidget();
    if (code >= 71 && code <= 77) return const SnowWidget();
    if (code >= 95) return const ThunderWidget();
    return const CloudWidget();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFF2C3E50),
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    if (_errorMessage.isNotEmpty) {
      return Scaffold(
        backgroundColor: const Color(0xFF2C3E50),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(_errorMessage, style: const TextStyle(color: Colors.white, fontSize: 16), textAlign: TextAlign.center),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: _getLocationAndWeather,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Повторить'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: _getBackgroundColors(_weatherCode),
              ),
            ),
          ),

          Positioned.fill(child: _buildWeatherEffect(_weatherCode)),

          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Верхняя панель с поиском
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Text(
                          _cityName,
                          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.search, color: Colors.white, size: 28),
                        onPressed: _showSearchDialog,
                        tooltip: 'Поиск города',
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Текущая температура
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        '${_currentTemp.round()}°',
                        style: const TextStyle(fontSize: 90, fontWeight: FontWeight.w200, color: Colors.white, height: 1),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        _getWeatherEmoji(_weatherCode),
                        style: const TextStyle(fontSize: 60),
                      ),
                    ],
                  ),
                  Text(
                    'Ощущается как ${_apparentTemp.round()}°',
                    style: const TextStyle(fontSize: 18, color: Colors.white70),
                  ),
                  const SizedBox(height: 20),

                  // Почасовой прогноз
                  const Text('Почасовой прогноз', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 100,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: _hourlyChartData.length,
                      itemBuilder: (context, index) {
                        final hour = _hourlyChartData[index];
                        final time = DateTime.parse(hour['time']);
                        return Container(
                          width: 70,
                          margin: const EdgeInsets.only(right: 10),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(DateFormat('HH:mm').format(time), style: const TextStyle(color: Colors.white70, fontSize: 12)),
                              const SizedBox(height: 4),
                              Text(_getWeatherEmoji(hour['code']), style: const TextStyle(fontSize: 22)),
                              const SizedBox(height: 4),
                              Text('${(hour['temp'] as num).round()}°', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 20),

                  // График температуры
                  const Text('График температуры', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 10),
                  Container(
                    height: 180,
                    padding: const EdgeInsets.only(top: 20, right: 20, left: 10),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 15,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: _buildHourlyChart(),
                  ),
                  const SizedBox(height: 20),

                  // Карточки показателей
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1.4,
                    children: [
                      _buildInfoCard('Влажность', '$_humidity%', '💧', Colors.blue),
                      _buildInfoCard('Ветер', '${_windSpeed.toStringAsFixed(1)} км/ч', '💨', Colors.lightBlue),
                      _buildInfoCard('Давление', '${_pressure.round()} мбар', '📊', Colors.orange),
                      _buildInfoCard('УФ-индекс', '${_uvIndex.round()} — ${_getUvLevel(_uvIndex)}', '☀️', _getUvColor(_uvIndex)),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Восход/Закат
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 15,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Expanded(child: _buildSunInfo('🌅 Восход', _formatTime(_sunrise))),
                        Container(width: 1, height: 40, color: Colors.white24),
                        Expanded(child: _buildSunInfo('🌇 Закат', _formatTime(_sunset))),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Прогноз на 5 дней с кнопкой "Подробнее"
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 15,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Прогноз на 5 дней', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
                            InkWell(
                              onTap: () => _showDetailedForecast(context),
                              child: const Padding(
                                padding: EdgeInsets.all(4.0),
                                child: Text('Подробнее >', style: TextStyle(color: Colors.white70)),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 15),
                        ..._dailyForecast.take(5).map((day) {
                          final date = DateTime.parse(day['date']);
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8.0),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 70,
                                  child: Text(
                                    DateFormat('EEE, d MMM', 'ru').format(date),
                                    style: const TextStyle(color: Colors.white, fontSize: 13),
                                  ),
                                ),
                                Text(_getWeatherEmoji(day['code']), style: const TextStyle(fontSize: 20)),
                                const Spacer(),
                                Text('${day['min'].round()}°', style: const TextStyle(color: Colors.white70)),
                                const SizedBox(width: 10),
                                Container(
                                  width: 60,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(3),
                                    gradient: const LinearGradient(colors: [Colors.blue, Colors.green, Colors.orange]),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Text('${day['max'].round()}°', style: const TextStyle(color: Colors.white)),
                              ],
                            ),
                          );
                        }).toList(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // === Экран "Подробнее" ===
  void _showDetailedForecast(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF2C3E50),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (context, scrollController) {
            return Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white30,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Подробный прогноз на 5 дней',
                    style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: ListView.builder(
                      controller: scrollController,
                      itemCount: _dailyForecast.take(5).length,
                      itemBuilder: (context, index) {
                        final day = _dailyForecast[index];
                        final date = DateTime.parse(day['date']);
                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    DateFormat('EEEE, d MMMM', 'ru').format(date),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(_getWeatherEmoji(day['code']), style: const TextStyle(fontSize: 32)),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  _buildDayDetail('🌡️ Мин/Макс', '${day['min'].round()}° / ${day['max'].round()}°'),
                                  _buildDayDetail('☀️ УФ-индекс', _getUvLevel((day['uv'] ?? 0).toDouble())),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildDayDetail(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white60, fontSize: 13)),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _buildSunInfo(String label, String time) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
        const SizedBox(height: 5),
        Text(time, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildHourlyChart() {
    if (_hourlyChartData.isEmpty) return const Center(child: Text('Нет данных', style: TextStyle(color: Colors.white)));

    double minTemp = _hourlyChartData.map((e) => e['temp'] as double).reduce((a, b) => a < b ? a : b);
    double maxTemp = _hourlyChartData.map((e) => e['temp'] as double).reduce((a, b) => a > b ? a : b);

    minTemp -= 2;
    maxTemp += 2;

    return LineChart(
      LineChartData(
        gridData: FlGridData(show: false),
        titlesData: FlTitlesData(
          show: true,
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 2,
              getTitlesWidget: (value, meta) {
                int index = value.toInt();
                if (index < 0 || index >= _hourlyChartData.length) return const SizedBox();
                if (index % 2 != 0) return const SizedBox();
                final time = DateTime.parse(_hourlyChartData[index]['time']);
                return Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text(
                    DateFormat('HH:mm').format(time),
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                );
              },
            ),
          ),
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        minX: 0,
        maxX: (_hourlyChartData.length - 1).toDouble(),
        minY: minTemp,
        maxY: maxTemp,
        lineBarsData: [
          LineChartBarData(
            spots: _hourlyChartData.asMap().entries.map((entry) {
              return FlSpot(entry.key.toDouble(), entry.value['temp'] as double);
            }).toList(),
            isCurved: true,
            color: Colors.lightGreenAccent,
            barWidth: 3,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                colors: [
                  Colors.lightGreenAccent.withOpacity(0.3),
                  Colors.lightGreenAccent.withOpacity(0.0),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(String title, String value, String emoji, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(color: Colors.white70, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}