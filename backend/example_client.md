Example clients

curl

curl -X POST "http://localhost:8000/detect" -F "image=@path/to/image.jpg"

Python example

```python
import requests

url = "http://localhost:8000/detect"
with open("test.jpg", "rb") as f:
    r = requests.post(url, files={"image": f})
    print(r.status_code)
    print(r.json())
```

Flutter (upload bytes)

- Convert a captured image or a PNG/JPEG file to bytes and send with multipart/form-data. Example using `http` package:

```dart
import 'package:http/http.dart' as http;

Future<void> uploadImage(Uint8List bytes) async {
  final uri = Uri.parse('http://10.0.2.2:8000/detect'); // emulator host -> host machine
  final req = http.MultipartRequest('POST', uri);
  req.files.add(http.MultipartFile.fromBytes('image', bytes, filename: 'frame.jpg'));
  final resp = await req.send();
  final body = await resp.stream.bytesToString();
  print('status: ${resp.statusCode}');
  print(body);
}
```

Notes: When running the Flutter app on Windows, use `http://localhost:8000/detect`. On Android emulator use `10.0.2.2`.
