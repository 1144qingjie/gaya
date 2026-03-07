# StoreKit 本地配置目录

把本地订阅联调用的 `.storekit` 文件放在这里，例如：

- `GayaMembership.storekit`

建议和以下商品 ID 保持一致：

- `com.gaya.membership.monthly`
- `com.gaya.membership.quarterly`

配置完后，在 Xcode 的 `gaya` scheme 里选择：

- `Product > Scheme > Edit Scheme...`
- `Run > Options > StoreKit Configuration`
