import { geoLocationManager } from '@kit.LocationKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { http } from '@kit.NetworkKit';
import { router } from '@kit.ArkUI';


const API_KEY: string = "Wye9POVjRr6ljeS3kSOOnQ==";
const MAX_STOPS_TO_SHOW: number = 3;

interface Stop {
  code: string;
  name: string;
  lat: number;
  lng: number;
  distance: number;
}

interface Location {
  lat: number;
  lng: number;
}

interface BusRouteEntry {
  ServiceNo: string;
  Direction: number;
  BusStopCode: string;
}

interface BusStopEntry {
  BusStopCode: string;
  Description: string;
  Latitude: number;
  Longitude: number;
}

interface ApiResponse {
  value: object[];
}

interface OneMapResult {
  SEARCHVAL: string;
  LATITUDE: string;
  LONGITUDE: string;
}

interface OneMapResponse {
  found: number;
  results: OneMapResult[];
}

interface NominatimResponse {
  lat: string;
  lon: string;
  display_name: string;
}

interface BusArrival {
  stopCode: string;
  stopName: string;
  distance: number;
  walkingMinutes: number;
  nextBus: string;
  nextBus2: string;
  nextBus3: string;
}

interface BusService {
  ServiceNo: string;
  NextBus: NextBusInfo;
  NextBus2: NextBusInfo;
  NextBus3: NextBusInfo;
}

interface NextBusInfo {
  EstimatedArrival: string;
}

interface ArrivalResponse {
  Services: BusService[];
}

function haversineDistance(
  lat1: number, lon1: number,
  lat2: number, lon2: number
): number {
  const R = 6371000;
  const dLat = (lat2 - lat1) * Math.PI / 180;
  const dLon = (lon2 - lon1) * Math.PI / 180;
  const a =
    Math.sin(dLat / 2) ** 2 +
      Math.cos(lat1 * Math.PI / 180) *
      Math.cos(lat2 * Math.PI / 180) *
        Math.sin(dLon / 2) ** 2;
  return R * 2 * Math.asin(Math.sqrt(a));
}

async function fetchAPI(url: string): Promise<ApiResponse> {
  return new Promise<ApiResponse>((resolve, reject) => {
    let request = http.createHttp();
    request.request(
      url,
      {
        method: http.RequestMethod.GET,
        header: { "AccountKey": API_KEY }
      },
      (err, data) => {
        if (err) {
          reject(err);
        } else {
          try {
            let parsed = JSON.parse(data.result.toString()) as ApiResponse;
            resolve(parsed);
          } catch (e) {
            reject(e);
          }
        }
      }
    );
  });
}

function getLocation(): Location {
  return { lat: 1.3521, lng: 103.8198 };
}

async function getStopsForBus(busNo: string): Promise<string[]> {
  let stops: string[] = [];
  let skip: number = 0;
  let pageCount: number = 0;

  while (true) {
    let url = `https://datamall2.mytransport.sg/ltaodataservice/BusRoutes?$skip=${skip}`;
    let result = await fetchAPI(url);

    pageCount++;
    hilog.info(0x0000, 'BusApp', 'Page %{public}d: got %{public}d records',
      pageCount, result.value ? result.value.length : 0);

    if (!result.value || result.value.length === 0) {
      break;
    }

    result.value.forEach((entry: object) => {
      let route = entry as BusRouteEntry;
      if (route.ServiceNo === busNo && route.Direction === 1) {
        stops.push(route.BusStopCode);
        hilog.info(0x0000, 'BusApp', 'Found stop: %{public}s', route.BusStopCode);
      }
    });

    if (result.value.length < 500) {
      break;
    }

    skip += 500;
  }

  hilog.info(0x0000, 'BusApp', 'Total stops found for bus %{public}s: %{public}d',
    busNo, stops.length);
  return stops;
}

async function geocodeWithOneMap(query: string): Promise<Location> {
  return new Promise<Location>((resolve, reject) => {
    let request = http.createHttp();
    let encodedQuery = encodeURIComponent(query);
    let url = `https://www.onemap.gov.sg/api/common/elastic/search?searchVal=${encodedQuery}&returnGeom=Y&getAddrDetails=Y&pageNum=1`;

    request.request(
      url,
      {
        method: http.RequestMethod.GET,
        header: { "Content-Type": "application/json" }
      },
      (err, data) => {
        if (err) { reject(err); return; }
        try {
          let parsed = JSON.parse(data.result.toString()) as OneMapResponse;
          if (!parsed.results || parsed.found === 0) {
            reject(new Error("Not found on OneMap"));
            return;
          }
          resolve({
            lat: parseFloat(parsed.results[0].LATITUDE),
            lng: parseFloat(parsed.results[0].LONGITUDE)
          });
        } catch (e) { reject(e); }
      }
    );
  });
}

async function geocodeLocation(query: string): Promise<Location> {
  return new Promise<Location>((resolve, reject) => {
    let request = http.createHttp();
    let encodedQuery = encodeURIComponent(query + " Singapore");
    let url = `https://nominatim.openstreetmap.org/search?q=${encodedQuery}&format=json&limit=1&countrycodes=sg`;

    request.request(
      url,
      {
        method: http.RequestMethod.GET,
        header: {
          "Content-Type": "application/json",
          "User-Agent": "LeaveNowApp/1.0"
        }
      },
      (err, data) => {
        if (err) {
          // Nominatim failed, try OneMap
          hilog.info(0x0000, 'BusApp', 'Nominatim failed, trying OneMap...');
          geocodeWithOneMap(query).then(resolve).catch(reject);
          return;
        }
        try {
          let results = JSON.parse(data.result.toString()) as NominatimResponse[];

          if (!results || results.length === 0) {
            // Nominatim returned nothing, try OneMap
            hilog.info(0x0000, 'BusApp', 'Nominatim empty, trying OneMap...');
            geocodeWithOneMap(query).then(resolve).catch(reject);
            return;
          }

          hilog.info(0x0000, 'BusApp', 'Nominatim found: %{public}s', results[0].display_name);
          resolve({
            lat: parseFloat(results[0].lat),
            lng: parseFloat(results[0].lon)
          });
        } catch (e) {
          geocodeWithOneMap(query).catch(reject);
        }
      }
    );
  });
}
async function getStopDetails(codes: string[]): Promise<Stop[]> {
  let stops: Stop[] = [];
  let skip: number = 0;

  while (true) {
    let url = `https://datamall2.mytransport.sg/ltaodataservice/BusStops?$skip=${skip}`;
    let result = await fetchAPI(url);

    if (!result.value || result.value.length === 0) {
      break;
    }

    result.value.forEach((entry: object) => {
      let s = entry as BusStopEntry;
      if (codes.includes(s.BusStopCode)) {
        let stop: Stop = {
          code: s.BusStopCode,
          name: s.Description,
          lat: s.Latitude,
          lng: s.Longitude,
          distance: 0
        };
        stops.push(stop);
      }
    });

    if (result.value.length < 500) {
      break;
    }

    skip += 500;
  }

  return stops;
}

function findNearestStops(
  userLat: number,
  userLng: number,
  stops: Stop[]
): Stop[] {
  stops.forEach((s: Stop) => {
    s.distance = haversineDistance(userLat, userLng, s.lat, s.lng);
  });
  stops.sort((a: Stop, b: Stop) => a.distance - b.distance);
  return stops.slice(0, MAX_STOPS_TO_SHOW);
}

// Calculate walking time from distance
function calcWalkingMinutes(distanceMeters: number): number {
  // Average walking speed is 1.4 meters per second
  return Math.ceil(distanceMeters / 1.4 / 60);
}

// Format arrival time to "X min" or "Arr"
function formatArrival(isoTime: string): string {
  if (!isoTime || isoTime === "") return "N/A";

  let arrival = new Date(isoTime);
  let now = new Date();
  let diffMs = arrival.getTime() - now.getTime();
  let diffMins = Math.floor(diffMs / 60000);

  if (diffMins <= 0) return "Arr";
  if (diffMins === 1) return "1 min";
  return `${diffMins} mins`;
}

// Fetch bus arrival for a specific stop
async function getBusArrival(stopCode: string, busNo: string): Promise<BusArrival | null> {
  return new Promise<BusArrival | null>((resolve) => {
    let request = http.createHttp();
    let url = `https://datamall2.mytransport.sg/ltaodataservice/v3/BusArrival?BusStopCode=${stopCode}&ServiceNo=${busNo}`;

    request.request(
      url,
      {
        method: http.RequestMethod.GET,
        header: { "AccountKey": API_KEY }
      },
      (err, data) => {
        if (err) {
          resolve(null);
          return;
        }
        try {
          let parsed = JSON.parse(data.result.toString()) as ArrivalResponse;

          if (!parsed.Services || parsed.Services.length === 0) {
            resolve(null);
            return;
          }

          let svc = parsed.Services[0];
          resolve({
            stopCode: stopCode,
            stopName: "",
            distance: 0,
            walkingMinutes: 0,
            nextBus: formatArrival(svc.NextBus.EstimatedArrival),
            nextBus2: formatArrival(svc.NextBus2.EstimatedArrival),
            nextBus3: formatArrival(svc.NextBus3.EstimatedArrival)
          });
        } catch (e) {
          resolve(null);
        }
      }
    );
  });
}

@Entry
@Component
struct BusApp {
  @State busNumber: string = "";
  @State locationQuery: string = "";
  @State results: Stop[] = [];
  @State loading: boolean = false;
  @State errorMsg: string = "";
  @State foundLocation: string = "";
  @State selectedStop: Stop | null = null;
  @State arrivalInfo: BusArrival | null = null;
  @State loadingArrival: boolean = false;

  build() {
    Scroll() {
      Column({ space: 12 }) {

        Text("🚌 LeaveNow")
          .fontSize(26)
          .fontWeight(FontWeight.Bold)
          .margin({ top: 20 })

        TextInput({ placeholder: "Enter bus number (e.g. 179)", text: this.busNumber })
          .width('90%')
          .height(48)
          .fontSize(16)
          .onChange((value: string) => {
            this.busNumber = value;
          })

        TextInput({ placeholder: "Enter your location (e.g. Clementi MRT)", text: this.locationQuery })
          .width('90%')
          .height(48)
          .fontSize(16)
          .onChange((value: string) => {
            this.locationQuery = value;
          })

        Button("Find Nearby Stops")
          .width('90%')
          .height(48)
          .fontSize(16)
          .backgroundColor('#007DFF')
          .onClick(() => {
            this.runSearch();
          })

        Text(this.foundLocation)
          .fontSize(13)
          .fontColor('#008800')
          .visibility(this.foundLocation.length > 0 ? Visibility.Visible : Visibility.None)

        LoadingProgress()
          .width(40)
          .height(40)
          .visibility(this.loading ? Visibility.Visible : Visibility.None)

        Text("Searching...")
          .fontSize(14)
          .visibility(this.loading ? Visibility.Visible : Visibility.None)

        Text(this.errorMsg)
          .fontSize(14)
          .fontColor('#FF0000')
          .visibility(this.errorMsg.length > 0 ? Visibility.Visible : Visibility.None)

        List({ space: 8 }) {
          ForEach(this.results, (stop: Stop) => {
            ListItem() {
              Column({ space: 4 }) {
                Text(stop.name)
                  .fontSize(16)
                  .fontWeight(FontWeight.Bold)
                Text(`Code: ${stop.code}`)
                  .fontSize(14)
                Text(`Distance: ${Math.round(stop.distance)} m`)
                  .fontSize(14)
                  .fontColor('#666666')
                Text(`🚶 ~${calcWalkingMinutes(stop.distance)} min walk`)
                  .fontSize(13)
                  .fontColor('#007DFF')
              }
              .padding(12)
              .width('100%')
              .backgroundColor(
                this.selectedStop !== null && this.selectedStop.code === stop.code
                  ? '#DCF0FF'
                  : '#F5F5F5'
              )
              .borderRadius(8)
              .onClick(() => {
                this.selectStop(stop);
              })
            }
          })
        }
        .width('90%')

        // Arrival info card
        Column({ space: 8 }) {
          Text(`📍 ${this.arrivalInfo !== null ? this.arrivalInfo.stopName : ""}`)
            .fontSize(16)
            .fontWeight(FontWeight.Bold)

          Text(`🚶 Walking time: ~${this.arrivalInfo !== null ? this.arrivalInfo.walkingMinutes : 0} min`)
            .fontSize(14)

          Row({ space: 12 }) {
            Column() {
              Text("Next Bus")
                .fontSize(12)
                .fontColor('#888888')
              Text(this.arrivalInfo !== null ? this.arrivalInfo.nextBus : "-")
                .fontSize(18)
                .fontWeight(FontWeight.Bold)
                .fontColor('#007DFF')
            }

            Column() {
              Text("2nd Bus")
                .fontSize(12)
                .fontColor('#888888')
              Text(this.arrivalInfo !== null ? this.arrivalInfo.nextBus2 : "-")
                .fontSize(18)
                .fontWeight(FontWeight.Bold)
                .fontColor('#007DFF')
            }

            Column() {
              Text("3rd Bus")
                .fontSize(12)
                .fontColor('#888888')
              Text(this.arrivalInfo !== null ? this.arrivalInfo.nextBus3 : "-")
                .fontSize(18)
                .fontWeight(FontWeight.Bold)
                .fontColor('#007DFF')
            }
          }
          .width('100%')
          .justifyContent(FlexAlign.SpaceEvenly)

          // Add this inside the arrival info Column, after the Row of bus times
          Button("OK → View Details")
            .width('100%')
            .height(44)
            .fontSize(15)
            .backgroundColor('#007DFF')
            .fontColor('#FFFFFF')
            .borderRadius(8)
            .onClick(() => {
              if (this.selectedStop !== null && this.arrivalInfo !== null) {
                router.pushUrl({
                  url: 'pages/BusDetail',
                  params: {
                    stopCode: this.selectedStop.code,
                    stopName: this.selectedStop.name,
                    busNumber: this.busNumber,
                    walkingMinutes: this.arrivalInfo.walkingMinutes,
                    distance: this.selectedStop.distance,
                    apiKey: API_KEY
                  }
                });
              }
            })
        }
        .width('90%')
        .padding(16)
        .backgroundColor('#FFFFFF')
        .borderRadius(12)
        .shadow({
          radius: 6,
          color: '#00000020',
          offsetX: 0,
          offsetY: 2
        })
        .visibility(this.arrivalInfo !== null ? Visibility.Visible : Visibility.None)

        // Loading arrival spinner
        LoadingProgress()
          .width(30)
          .height(30)
          .visibility(this.loadingArrival ? Visibility.Visible : Visibility.None)
        Text("Fetching arrival times...")
          .fontSize(13)
          .visibility(this.loadingArrival ? Visibility.Visible : Visibility.None)

      }
      .width('100%')
      .padding(20)
    }
    .width('100%')
    .height('100%')
  }

  runSearch(): void {
    if (this.busNumber === "") {
      this.errorMsg = "Please enter a bus number first!";
      return;
    }
    if (this.locationQuery === "") {
      this.errorMsg = "Please enter your location!";
      return;
    }

    this.loading = true;
    this.errorMsg = "";
    this.results = [];
    this.foundLocation = "";



    // Step 1: Geocode the location first
    geocodeLocation(this.locationQuery)
      .then((loc: Location) => {
        this.foundLocation = `📍 Using: ${this.locationQuery} (${loc.lat.toFixed(4)}, ${loc.lng.toFixed(4)})`;

        // Step 2: Get bus stops
        return getStopsForBus(this.busNumber)
          .then((codes: string[]) => {
            if (codes.length === 0) {
              this.errorMsg = "No stops found for this bus number.";
              this.loading = false;
              return;
            }

            // Step 3: Get stop details
            return getStopDetails(codes)
              .then((stops: Stop[]) => {
                // Step 4: Find nearest
                this.results = findNearestStops(loc.lat, loc.lng, stops);
                this.loading = false;
              });
          });
      })
      .catch((err: Error) => {
        hilog.error(0x0000, 'BusApp', 'Error: %{public}s', JSON.stringify(err));
        this.errorMsg = "Could not find location. Try a more specific name!";
        this.loading = false;
      });
  }

  // 👇 ADD selectStop() RIGHT HERE
  selectStop(stop: Stop): void {
    this.selectedStop = stop;
    this.arrivalInfo = null;
    this.loadingArrival = true;

    getBusArrival(stop.code, this.busNumber)
      .then((arrival: BusArrival | null) => {
        if (arrival !== null) {
          arrival.stopName = stop.name;
          arrival.distance = stop.distance;
          arrival.walkingMinutes = calcWalkingMinutes(stop.distance);
          this.arrivalInfo = arrival;
        } else {
          this.errorMsg = "No arrival info available for this stop.";
        }
        this.loadingArrival = false;
      })
      .catch((err: Error) => {
        this.errorMsg = "Failed to fetch arrival times.";
        this.loadingArrival = false;
      });
  }   // ← closes selectStop()
}