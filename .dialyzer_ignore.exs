# Known MapSet/:sets opacity false positives on recent OTP. Keep each exclusion
# bound to one warning at one line/column; other warnings in these files still fail.
# OTP 28 reports {line, column} locations, which Dialyxir matches exactly.
[
  {"lib/media/asset_store.ex", :call_without_opaque, {143, 23}},
  {"lib/media/asset_store.ex", :call_without_opaque, {155, 23}},
  {"lib/media/asset_store.ex", :call_without_opaque, {167, 23}},
  {"lib/menu/contribution_validator.ex", :call_without_opaque, {95, 23}},
  {"lib/menu/contribution_validator.ex", :call_with_opaque, {101, 48}},
  {"lib/schedule/scheduler.ex", :call_without_opaque, {108, 13}},
  {"lib/workflow/process_definition.ex", :call_without_opaque, {114, 22}}
]
