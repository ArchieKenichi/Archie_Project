import { hilog } from '@kit.PerformanceAnalysisKit';
import { http } from '@kit.NetworkKit';
import { router } from '@kit.ArkUI';

// --- Interfaces ---
interface NextBusInfo {
  EstimatedArrival: string;
  Latitude: string;
  Longitude: string;
  Load: string;
  Feature: string;
}

interface BusService {
  ServiceNo: string;
  NextBus: NextBusInfo;
  NextBus2: NextBusInfo;
  NextBus3: NextBusInfo;
}

interface ArrivalResponse {
  Services: BusService[];
}

interface PageParams {
  stopCode: string;
  stopName: string;
  busNumber: string;
  walkingMinutes: number;
  distance: number;
  apiKey: string;
}

// --- Helpers ---
function formatArrival(isoTime: string): string {
  if (!isoTime || isoTime === "") return "N/A";
  let arrival = new Date(isoTime);
  let now = new Date();
  let diffMins = Math.floor((arrival.getTime() - now.getTime()) / 60000);
  if (diffMins <= 0) return "Arr";
  if (diffMins === 1) return "1 min";
  return `${diffMins} mins`;
}

function getArrivalMinutes(isoTime: string): number {
  if (!isoTime || isoTime === "") return 999;
  let arrival = new Date(isoTime);
  let now = new Date();
  return Math.floor((arrival.getTime() - now.getTime()) / 60000);
}

function getRecommendation(walkMins: number, busMins: number): string {
  let diff = busMins - walkMins;

  if (busMins === 999 || busMins < 0) {
    return "⏳ No upcoming bus data available.";
  }

  if (diff <= 0) {
    return "🏃 RUSH NOW! The bus arrives before you can walk there!";
  } else if (diff <= 2) {
    return "🚶‍♂️ Walk briskly! You have just enough time.";
  } else if (diff <= 5) {
    return "😊 You can walk comfortably, no need to rush!";
  } else {
    return "🧘 Take your time, the bus is not arriving soon.";
  }
}

function getRecommendationColor(walkMins: number, busMins: number): string {
  let diff = busMins - walkMins;
  if (busMins === 999) return '#888888';
  if (diff <= 0) return '#FF3B30';   // red - rush
  if (diff <= 2) return '#FF9500';   // orange - walk briskly
  if (diff <= 5) return '#34C759';   // green - comfortable
  return '#007DFF';                   // blue - lots of time
}

function getBusLoadLabel(load: string): string {
  if (load === "SEA") return "🟢 Seats Available";
  if (load === "SDA") return "🟡 Standing Available";
  if (load === "LSD") return "🔴 Bus is Full";
  return "⚪ Unknown";
}

// --- Page ---
@Entry
@Component
struct BusDetailPage {
  @State stopCode: string = "";
  @State stopName: string = "";
  @State busNumber: string = "";
  @State walkingMinutes: number = 0;
  @State distance: number = 0;
  @State apiKey: string = "";

  @State nextBus: string = "-";
  @State nextBus2: string = "-";
  @State nextBus3: string = "-";
  @State nextBusMins: number = 999;
  @State busLoad: string = "";
  @State loading: boolean = true;
  @State errorMsg: string = "";
  @State lastUpdated: string = "";

  private refreshTimer: number = -1;

  aboutToAppear(): void {
    // Get params passed from Index.ets
    let params = router.getParams() as PageParams;
    this.stopCode = params.stopCode;
    this.stopName = params.stopName;
    this.busNumber = params.busNumber;
    this.walkingMinutes = params.walkingMinutes;
    this.distance = params.distance;
    this.apiKey = params.apiKey;

    // Fetch immediately and then every 30 seconds
    this.fetchArrival();
    this.refreshTimer = setInterval(() => {
      this.fetchArrival();
    }, 30000);
  }

  aboutToDisappear(): void {
    // Clean up timer when leaving page
    if (this.refreshTimer !== -1) {
      clearInterval(this.refreshTimer);
    }
  }

  fetchArrival(): void {
    let request = http.createHttp();
    let url = `https://datamall2.mytransport.sg/ltaodataservice/v3/BusArrival?BusStopCode=${this.stopCode}&ServiceNo=${this.busNumber}`;

    request.request(
      url,
      {
        method: http.RequestMethod.GET,
        header: { "AccountKey": this.apiKey }
      },
      (err, data) => {
        if (err) {
          this.errorMsg = "Failed to fetch arrival data.";
          this.loading = false;
          return;
        }
        try {
          let parsed = JSON.parse(data.result.toString()) as ArrivalResponse;

          if (!parsed.Services || parsed.Services.length === 0) {
            this.errorMsg = "No bus service data available.";
            this.loading = false;
            return;
          }

          let svc = parsed.Services[0];
          this.nextBus = formatArrival(svc.NextBus.EstimatedArrival);
          this.nextBus2 = formatArrival(svc.NextBus2.EstimatedArrival);
          this.nextBus3 = formatArrival(svc.NextBus3.EstimatedArrival);
          this.nextBusMins = getArrivalMinutes(svc.NextBus.EstimatedArrival);
          this.busLoad = svc.NextBus.Load;

          // Update last refreshed time
          let now = new Date();
          this.lastUpdated = `Last updated: ${now.getHours()}:${now.getMinutes().toString().padStart(2, '0')}:${now.getSeconds().toString().padStart(2, '0')}`;
          this.loading = false;
          this.errorMsg = "";
        } catch (e) {
          this.errorMsg = "Error parsing bus data.";
          this.loading = false;
        }
      }
    );
  }

  build() {
    Column({ space: 16 }) {

      // --- Header ---
      Row() {
        Button("← Back")
          .fontSize(14)
          .backgroundColor('#F0F0F0')
          .fontColor('#000000')
          .height(36)
          .onClick(() => {
            router.back();
          })
        Blank()
        Text(`Bus ${this.busNumber}`)
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
      }
      .width('100%')
      .padding({ top: 20, left: 16, right: 16 })

      // --- Stop Info ---
      Column({ space: 4 }) {
        Text(this.stopName)
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .textAlign(TextAlign.Center)
        Text(`Stop Code: ${this.stopCode}`)
          .fontSize(13)
          .fontColor('#888888')
        Text(`📍 ${Math.round(this.distance)} m away`)
          .fontSize(13)
          .fontColor('#888888')
        Text(`🚶 ~${this.walkingMinutes} min walk`)
          .fontSize(13)
          .fontColor('#007DFF')
      }
      .width('90%')
      .padding(16)
      .backgroundColor('#F5F5F5')
      .borderRadius(12)

      // --- Recommendation Card ---
      Column({ space: 8 }) {
        Text("Should you rush?")
          .fontSize(14)
          .fontColor('#888888')
        Text(getRecommendation(this.walkingMinutes, this.nextBusMins))
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(getRecommendationColor(this.walkingMinutes, this.nextBusMins))
          .textAlign(TextAlign.Center)

        // Visual urgency bar
        Row() {
          Text("🚶 You")
            .fontSize(12)
          Blank()
          Text(`🚌 Bus in ${this.nextBusMins === 999 ? "?" : this.nextBusMins} min`)
            .fontSize(12)
        }
        .width('100%')

        Progress({
          value: this.nextBusMins === 999 ? 0 :
            Math.min(100, Math.max(0,
              (this.nextBusMins / (this.walkingMinutes + 5)) * 100
            )),
          total: 100,
          type: ProgressType.Linear
        })
          .width('100%')
          .color(getRecommendationColor(this.walkingMinutes, this.nextBusMins))
      }
      .width('90%')
      .padding(16)
      .backgroundColor('#FFFFFF')
      .borderRadius(12)
      .shadow({ radius: 6, color: '#00000020', offsetX: 0, offsetY: 2 })

      // --- Arrival Times Card ---
      Column({ space: 12 }) {
        Text("🕐 Arrival Times")
          .fontSize(16)
          .fontWeight(FontWeight.Bold)

        Text(getBusLoadLabel(this.busLoad))
          .fontSize(13)

        Row({ space: 12 }) {
          Column({ space: 4 }) {
            Text("Next Bus")
              .fontSize(12)
              .fontColor('#888888')
            Text(this.nextBus)
              .fontSize(22)
              .fontWeight(FontWeight.Bold)
              .fontColor('#007DFF')
          }
          Column({ space: 4 }) {
            Text("2nd Bus")
              .fontSize(12)
              .fontColor('#888888')
            Text(this.nextBus2)
              .fontSize(22)
              .fontWeight(FontWeight.Bold)
              .fontColor('#007DFF')
          }
          Column({ space: 4 }) {
            Text("3rd Bus")
              .fontSize(12)
              .fontColor('#888888')
            Text(this.nextBus3)
              .fontSize(22)
              .fontWeight(FontWeight.Bold)
              .fontColor('#007DFF')
          }
        }
        .width('100%')
        .justifyContent(FlexAlign.SpaceEvenly)

        Text(this.lastUpdated)
          .fontSize(11)
          .fontColor('#AAAAAA')

        // Manual refresh button
        Button("🔄 Refresh")
          .width('100%')
          .height(40)
          .fontSize(14)
          .backgroundColor('#F0F0F0')
          .fontColor('#000000')
          .onClick(() => {
            this.loading = true;
            this.fetchArrival();
          })
      }
      .width('90%')
      .padding(16)
      .backgroundColor('#FFFFFF')
      .borderRadius(12)
      .shadow({ radius: 6, color: '#00000020', offsetX: 0, offsetY: 2 })

      // Loading / Error
      LoadingProgress()
        .width(30)
        .height(30)
        .visibility(this.loading ? Visibility.Visible : Visibility.None)

      Text(this.errorMsg)
        .fontSize(14)
        .fontColor('#FF0000')
        .visibility(this.errorMsg.length > 0 ? Visibility.Visible : Visibility.None)

    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F8F8F8')
  }
}