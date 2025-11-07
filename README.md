I’m building a Flutter frontend for a Smart CCTV Detection module.
It has two main AI functions:

Environmental Awareness – shows lighting intensity, dark zones, and environmental risk levels on a map.

Suspicious Behavior Detection – displays live CCTV feeds, flags suspicious activities (like abnormal movement or clothing), and sends security alerts in real-time.

Please:

Set up a Flutter app structure (using MVVM or clean architecture).

Include pages: Dashboard, Live Feed, Alerts, Map View.

Use Google Maps or Mapbox to show dynamic risk zones (colored overlays for safe/unsafe areas).

Add WebSocket or Firebase integration for real-time alerts and data updates.

Use REST API calls to retrieve data from the backend AI (camera status, predictions, etc.).

Recommend libraries for:

State management (e.g., Riverpod, Bloc, or Provider)

Map visualization

Real-time video feed streaming

Push notifications

UI design (modern dashboard style)

Include example Flutter code for one page (e.g., Live Feed screen with a CCTV camera view and alert list).

Suggest how to visualize AI detection results — e.g., bounding boxes or risk indicators overlaying the camera feed.

python -m venv .venv  
. .\.venv\Scripts\Activate.ps1

python -m uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
