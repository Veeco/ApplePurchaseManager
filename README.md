# ApplePurchaseManager

一个用于处理苹果应用内购买的Swift Package Manager库，提供简单易用的API来管理应用内购买流程。

## 功能特性

- ✅ 支持应用内购买
- ✅ 支持恢复购买
- ✅ 多代理模式支持
- ✅ 完整的错误处理
- ✅ 收据验证
- ✅ 交易状态管理
- ✅ 支持iOS 13+, macOS 10.15+, tvOS 13+, watchOS 6+

## 安装

### Swift Package Manager

在Xcode中，选择 `File` > `Add Package Dependencies...`，然后输入以下URL：

```
https://github.com/Veeco/ApplePurchaseManager.git
```

或者在你的 `Package.swift` 文件中添加依赖：

```swift
dependencies: [
    .package(url: "https://github.com/Veeco/ApplePurchaseManager.git", from: "1.0.0")
]
```

## 使用方法

### 1. 导入库

```swift
import ApplePurchaseManager
```

### 2. 实现代理

```swift
class ViewController: UIViewController, ApplePurchaseManagerDelegate {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // 添加购买代理
        ApplePurchaseManager.addDelegate(self)
    }
    
    deinit {
        // 移除购买代理
        ApplePurchaseManager.removeDelegate(self)
    }
    
    // MARK: - ApplePurchaseManagerDelegate
    
    func applePurchaseManager(_ manager: ApplePurchaseManager, didCompletePurchase result: PurchaseResult) {
        print("购买成功:")
        print("产品ID: \(result.productIdentifier)")
        print("交易ID: \(result.transactionIdentifier)")
        print("用户ID: \(result.userID)")
        print("收据数据: \(result.receiptData)")
        
        // 在这里将购买信息发送到你的服务器进行验证
        // 验证成功后调用 finishTransaction 完成交易
        let error = ApplePurchaseManager.finishTransaction(transactionIdentifier: result.transactionIdentifier)
        if let error = error {
            print("完成交易失败: \(error)")
        }
    }
    
    func applePurchaseManager(_ manager: ApplePurchaseManager, didFailWithError error: PurchaseError) {
        print("购买失败: \(error.localizedDescription)")
        
        // 处理不同类型的错误
        switch error {
        case .userCancelled:
            // 用户取消购买
            break
        case .deviceNotSupported:
            // 设备不支持内购
            break
        case .productNotFound(let productId):
            // 产品未找到
            print("产品未找到: \(productId)")
            break
        default:
            // 其他错误
            break
        }
    }
}
```

### 3. 发起购买

```swift
// 购买产品
ApplePurchaseManager.purchaseProduct(productID: "com.yourapp.product1", userID: "user123")
```

### 4. 恢复购买

```swift
// 恢复之前的购买
ApplePurchaseManager.restoreCompletedTransactions()
```

## 数据结构

### PurchaseResult

购买成功时返回的结果：

```swift
struct PurchaseResult {
    let productIdentifier: String    // 产品标识符
    let transactionIdentifier: String // 交易标识符
    let receiptData: String          // 收据数据（Base64编码）
    let userID: String               // 用户ID
}
```

### PurchaseError

购买失败时的错误类型：

```swift
enum PurchaseError: Error {
    case deviceNotSupported          // 设备不支持应用内购买
    case productNotFound(String)     // 产品未找到
    case noProductsAvailable         // 没有可用的商品
    case transactionInProgress       // 已有交易正在进行中
    case receiptValidationFailed     // 收据验证失败
    case userCancelled              // 用户取消购买
    case paymentNotAllowed          // 不允许支付
    case paymentInvalid             // 支付无效
    case paymentDeferred            // 支付被延迟
    case unknown(String)            // 未知错误
}
```

## 重要注意事项

1. **交易完成**: 在收到购买成功回调后，必须将购买信息发送到服务器进行验证，验证成功后调用 `finishTransaction` 方法完成交易。

2. **代理管理**: 记得在适当的时候添加和移除代理，避免内存泄漏。

3. **错误处理**: 务必处理所有可能的错误情况，为用户提供良好的体验。

4. **测试**: 在开发过程中使用沙盒环境进行测试，确保所有功能正常工作。

## 许可证

MIT License

## 贡献

欢迎提交Issue和Pull Request来改进这个库。

## 支持

如果你在使用过程中遇到问题，请创建一个Issue，我们会尽快回复。