$headers = @{
  "apikey" = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJ1cW9ueXVvanR2eGFudWF1dGFuIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODI4ODI5MTIsImV4cCI6MjA5ODQ1ODkxMn0.Z585bKSBUFt0IRP3haB2cJ1kEpDcv0C-Hr8N89Pvm58"
  "Authorization" = "Bearer eyJhbGciOiJFUzI1NiIsImtpZCI6ImRiNmRkNzliLTliMzMtNDVmOS04YjQ3LTc0Nzg3ODBjNmRlOCIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJodHRwczovL2J1cW9ueXVvanR2eGFudWF1dGFuLnN1cGFiYXNlLmNvL2F1dGgvdjEiLCJzdWIiOiI4NGI3Yzk1Ny1lMTQ1LTQ0NmEtOWEzMS0wNTFmMmNiOWIzYWYiLCJhdWQiOiJhdXRoZW50aWNhdGVkIiwiZXhwIjoxNzgyODk2OTQ5LCJpYXQiOjE3ODI4OTMzNDksImVtYWlsIjoic2FrZXRAc2t1bWFyY3JlYXRpb24uY29tIiwicGhvbmUiOiIiLCJhcHBfbWV0YWRhdGEiOnsicHJvdmlkZXIiOiJlbWFpbCIsInByb3ZpZGVycyI6WyJlbWFpbCJdfSwidXNlcl9tZXRhZGF0YSI6eyJlbWFpbF92ZXJpZmllZCI6dHJ1ZX0sInJvbGUiOiJhdXRoZW50aWNhdGVkIiwiYWFsIjoiYWFsMSIsImFtciI6W3sibWV0aG9kIjoicGFzc3dvcmQiLCJ0aW1lc3RhbXAiOjE3ODI4OTMzNDl9XSwic2Vzc2lvbl9pZCI6ImQwNmRiZjU5LTE2MjEtNDdkNS1hM2Q1LTc1N2RkYzQ0MWY0YiIsImlzX2Fub255bW91cyI6ZmFsc2V9.o34Quspxkm_Yr5L0ueog1czpxdzuJR6vg90I0kpLtiTCTR2log5tmTxX7W4eTCZjhZjMV08H06Aj5Dts_9b8VQ"
  "Content-Type" = "application/json"
  "Prefer" = "return=representation"
}
$body = '{"name":"Test Site","address":"123 Test St","site_login_id":"test1234567","site_password_hash":"hash123","created_by":"84b7c957-e145-446a-9a31-051f2cb9b3af"}'
try {
  $response = Invoke-RestMethod -Uri "https://buqonyuojtvxanuautan.supabase.co/rest/v1/sites" -Method POST -Headers $headers -Body $body
  $response | ConvertTo-Json
} catch {
  $_.Exception.Response | Out-String
  $stream = $_.Exception.Response.GetResponseStream()
  $reader = New-Object System.IO.StreamReader($stream)
  $reader.ReadToEnd()
}
