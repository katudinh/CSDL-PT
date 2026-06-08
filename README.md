# CÁC BƯỚC CHẠY SCRIPT SQL

## 1. Yêu cầu cài đặt

Cài đặt:

* Microsoft SQL Server
* SQL Server Management Studio

## 2. Mở file script

Mở SQL Server Management Studio, sau đó mở file:

```text
vehicletelematics.sql
```

## 3. Chạy script

Nhấn:

```text
Execute
```

hoặc bấm phím:

```text
F5
```

Script sẽ chạy theo các bước chính sau:

## 4. Các bước xử lý trong script

### Bước 1: Reset và tạo database

Script sẽ xóa database cũ nếu đã tồn tại, sau đó tạo lại database:

```text
VehicleTelematicsDB
```

### Bước 2: Tạo bảng dữ liệu gốc

Tạo bảng:

```text
VehicleLogs
```

Bảng này lưu dữ liệu telematics của xe, gồm các cột:

```text
Timestamp, VIN, Speed, FuelLevel, Location, EngineTemp
```

### Bước 3: Generate 10.000 dòng dữ liệu

Script tự động sinh 10.000 dòng dữ liệu giả lập cho bảng `VehicleLogs`.

### Bước 4: Kiểm tra dữ liệu gốc

Kiểm tra số lượng dữ liệu trong bảng `VehicleLogs`.

Kết quả mong đợi:

```text
OriginalRecordCount = 10000
```

### Bước 5: Phân mảnh ngang dữ liệu

Dữ liệu được chia thành 4 horizontal fragments theo khoảng `VIN`:

```text
H1: VIN000001 - VIN002500
H2: VIN002501 - VIN005000
H3: VIN005001 - VIN007500
H4: VIN007501 - VIN010000
```

### Bước 6: Kiểm tra phân mảnh ngang

Kiểm tra số dòng của các bảng `H1`, `H2`, `H3`, `H4`.

Kết quả mong đợi:

```text
H1 = 2500
H2 = 2500
H3 = 2500
H4 = 2500
```

### Bước 7: Phân mảnh dọc dữ liệu

Mỗi fragment ngang tiếp tục được chia thành 2 fragment dọc:

```text
Operational: Timestamp, VIN, Speed, FuelLevel, Location
Diagnostic: Timestamp, VIN, EngineTemp
```

Các bảng được tạo ra gồm:

```text
H1_Operational, H1_Diagnostic
H2_Operational, H2_Diagnostic
H3_Operational, H3_Diagnostic
H4_Operational, H4_Diagnostic
```

### Bước 8: Kiểm tra phân mảnh dọc

Kiểm tra số dòng của 8 bảng fragment dọc.

Kết quả mong đợi:

```text
Mỗi bảng fragment dọc có 2500 dòng
```

### Bước 9: Khôi phục dữ liệu trước khi tạo lỗi

Script khôi phục dữ liệu bằng cách:

```text
JOIN Operational với Diagnostic theo VIN + Timestamp
UNION ALL các fragment đã khôi phục
```

Kết quả được lưu vào bảng:

```text
ReconstructedVehicleLogs
```

### Bước 10: Xác thực dữ liệu trước khi tạo lỗi

Kiểm tra số dòng của bảng `ReconstructedVehicleLogs`.

Kết quả mong đợi:

```text
ReconstructedRecordCountBeforeFailure = 10000
ValidationResultBeforeFailure = PASS
```

### Bước 11: Mô phỏng lỗi mất dữ liệu

Script xóa ngẫu nhiên 30 dòng từ bảng:

```text
H3_Operational
```

Các dòng bị xóa được lưu lại trong bảng:

```text
DeletedRecords
```

Kết quả mong đợi:

```text
DeletedRecordCount = 30
H3_Operational còn lại 2470 dòng
```

### Bước 12: Khôi phục dữ liệu sau khi tạo lỗi

Script chạy reconstruction lại sau khi đã xóa dữ liệu.

Kết quả được lưu vào bảng:

```text
ReconstructedVehicleLogs_AfterFailure
```

Kết quả mong đợi:

```text
ReconstructedRecordCountAfterFailure = 9970
```

### Bước 13: Tạo báo cáo xác thực tự động

Script tạo bảng:

```text
ValidationReport_Auto
```

Bảng này tự động phát hiện:

```text
Mất record nào
Mất ở fragment nào
Loại lỗi là gì
Cột nào bị ảnh hưởng
```

Vì script đang xóa dữ liệu ở `H3_Operational`, kết quả mong đợi là:

```text
ErrorType = Missing Operational Record
MissingFragment = H3_Operational
MissingColumn = Speed, FuelLevel, Location
ErrorCount = 30
```

### Bước 14: Tạo bảng tổng kết lỗi

Script tạo bảng:

```text
FinalValidationSummary
```

Bảng này cho biết mất dữ liệu ở đâu và mất bao nhiêu record.

Kết quả mong đợi:

```text
Vị trí mất dữ liệu: H3_Operational
Loại lỗi: Missing Operational Record
Số record bị mất: 30
```

### Bước 15: Hiển thị kết quả cuối cùng

Script hiển thị bảng tổng kết cuối cùng gồm:

```text
Original records
Reconstructed records before failure
Reconstructed records after failure
Missing records
Missing location
Validation result
```

Kết quả mong đợi:

```text
Original records = 10000
Reconstructed records before failure = 10000
Reconstructed records after failure = 9970
Missing records = 30
Missing location = H3_Operational = 30 records
Validation result = FAIL
```

## 5. Kiểm tra kết quả quan trọng

Sau khi chạy script, kiểm tra các bảng sau:

```sql
SELECT COUNT(*) AS OriginalRecordCount
FROM dbo.VehicleLogs;
```

```sql
SELECT COUNT(*) AS ReconstructedRecordCountBeforeFailure
FROM dbo.ReconstructedVehicleLogs;
```

```sql
SELECT COUNT(*) AS ReconstructedRecordCountAfterFailure
FROM dbo.ReconstructedVehicleLogs_AfterFailure;
```

```sql
SELECT *
FROM dbo.ValidationReport_Auto
ORDER BY FragmentName, VIN;
```

```sql
SELECT *
FROM dbo.FinalValidationSummary;
```


