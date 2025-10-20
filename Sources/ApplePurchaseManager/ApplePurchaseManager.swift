//
//  ApplePurchaseManager.swift
//  Interactipie
//
//  Created by Interactipie Team.
//

import Foundation
import StoreKit

public protocol ApplePurchaseManagerDelegate: AnyObject {
    func applePurchaseManager(_ manager: ApplePurchaseManager, didCompletePurchase result: PurchaseResult)
    func applePurchaseManager(_ manager: ApplePurchaseManager, didFailWithError error: PurchaseError)
}

public struct PurchaseResult {
    public let productIdentifier: String
    public let transactionIdentifier: String
    public let receiptData: String
    public let userID: String
}

public enum PurchaseError: Error {
    case deviceNotSupported
    case productNotFound(String)
    case noProductsAvailable
    case transactionInProgress
    case receiptValidationFailed
    case userCancelled
    case paymentNotAllowed
    case paymentInvalid
    case paymentDeferred
    case unknown(String)
    
    var localizedDescription: String {
        switch self {
        case .deviceNotSupported:
            return "设备不支持应用内购买"
        case .productNotFound(let identifier):
            return "产品未找到: \(identifier)"
        case .noProductsAvailable:
            return "没有可用的商品"
        case .transactionInProgress:
            return "已有交易正在进行中，请稍后再试"
        case .receiptValidationFailed:
            return "收据验证失败"
        case .userCancelled:
            return "用户取消购买"
        case .paymentNotAllowed:
            return "不允许支付"
        case .paymentInvalid:
            return "支付无效"
        case .paymentDeferred:
            return "支付被延迟"
        case .unknown(let message):
            return message
        }
    }
}

public class ApplePurchaseManager: NSObject {
    
    private static let shared = ApplePurchaseManager()
    
    private var isTransactionInProgress = false
    private var delegates = NSHashTable<AnyObject>.weakObjects()
    private var currentUserID: String?
    private var pendingTransactions = [String: SKPaymentTransaction]()
    
    private override init() {
        super.init()
        SKPaymentQueue.default().add(self)
    }
    
    deinit {
        SKPaymentQueue.default().remove(self)
    }
    
    // MARK: - Public Methods
    
    /// 添加购买代理
    /// - Parameter delegate: 购买代理对象
    public static func addDelegate(_ delegate: ApplePurchaseManagerDelegate) {
        let instance = ApplePurchaseManager.shared
        instance.delegates.add(delegate)
    }
    
    /// 移除购买代理
    /// - Parameter delegate: 购买代理对象
    public static func removeDelegate(_ delegate: ApplePurchaseManagerDelegate) {
        let instance = ApplePurchaseManager.shared
        instance.delegates.remove(delegate)
    }
    
    public static func purchaseProduct(productID: String, userID: String) {
        let instance = ApplePurchaseManager.shared
        
        // 检查是否已有交易在进行中
        guard !instance.isTransactionInProgress else {
            instance.notifyDelegatesFailure(PurchaseError.transactionInProgress)
            return
        }
        
        // 检查设备是否支持内购
        guard SKPaymentQueue.canMakePayments() else {
            instance.notifyDelegatesFailure(PurchaseError.deviceNotSupported)
            return
        }
        
        // 设置交易状态
        instance.isTransactionInProgress = true
        instance.currentUserID = userID
        
        instance.loadProducts(productIdentifiers: Set([productID]))
    }
    
    /// 完成交易 - 在与后端确认订单后调用
    /// - Parameter transactionIdentifier: 交易标识符
    /// - Returns: 错误信息
    public static func finishTransaction(transactionIdentifier: String) -> String? {
        let instance = ApplePurchaseManager.shared
        
        guard let transaction = instance.pendingTransactions[transactionIdentifier] else {
            return "未找到待完成的交易: \(transactionIdentifier)"
        }
        
        // 完成交易
        instance.finishTransaction(transaction)
        
        // 从缓存中移除
        instance.pendingTransactions.removeValue(forKey: transactionIdentifier)
        
        return nil
    }
    
    public static func restoreCompletedTransactions() {
        SKPaymentQueue.default().restoreCompletedTransactions()
    }
    
    private func loadProducts(productIdentifiers: Set<String>) {
        let request = SKProductsRequest(productIdentifiers: productIdentifiers)
        request.delegate = self
        request.start()
    }
    
    private func proceedWithPurchase(product: SKProduct) {
        // 开始购买
        let payment = SKMutablePayment(product: product)
        if let userID = currentUserID {
            payment.applicationUsername = userID
        }
        SKPaymentQueue.default().add(payment)
    }
    
    private func finishTransaction(_ transaction: SKPaymentTransaction) {
        SKPaymentQueue.default().finishTransaction(transaction)
    }
    
    private func resetTransactionState() {
        isTransactionInProgress = false
        currentUserID = nil
    }
    
    // MARK: - Private Delegate Methods
    
    private func notifyDelegatesSuccess(_ result: PurchaseResult) {
        for delegate in delegates.allObjects {
            (delegate as? ApplePurchaseManagerDelegate)?.applePurchaseManager(self, didCompletePurchase: result)
        }
    }
    
    private func notifyDelegatesFailure(_ error: PurchaseError) {
        for delegate in delegates.allObjects {
            (delegate as? ApplePurchaseManagerDelegate)?.applePurchaseManager(self, didFailWithError: error)
        }
    }
}

// MARK: - SKProductsRequestDelegate

extension ApplePurchaseManager: SKProductsRequestDelegate {
    
    public func productsRequest(_ request: SKProductsRequest, didReceive response: SKProductsResponse) {
        let products = response.products
        
        // 检查商品数量是否为0
        if products.isEmpty {
            notifyDelegatesFailure(PurchaseError.noProductsAvailable)
            resetTransactionState()
            return
        }
        
        // 继续购买流程
        if let product = products.first {
            proceedWithPurchase(product: product)
        }
    }
    
    public func request(_ request: SKRequest, didFailWithError error: Error) {
        // 回调失败
        notifyDelegatesFailure(PurchaseError.unknown("产品加载失败: \(error.localizedDescription)"))
        resetTransactionState()
    }
}

// MARK: - SKPaymentTransactionObserver

extension ApplePurchaseManager: SKPaymentTransactionObserver {
    
    public func paymentQueue(_ queue: SKPaymentQueue, updatedTransactions transactions: [SKPaymentTransaction]) {
        for transaction in transactions {
            switch transaction.transactionState {
            case .purchasing:
                print("正在购买: \(transaction.payment.productIdentifier)")
                
            case .purchased:
                print("购买成功: \(transaction.payment.productIdentifier)")
                handlePurchasedTransaction(transaction)
                
            case .failed:
                print("购买失败: \(transaction.error?.localizedDescription ?? "未知错误")")
                handleFailedTransaction(transaction)
                
            case .restored:
                print("恢复购买: \(transaction.payment.productIdentifier)")
                handlePurchasedTransaction(transaction)
                
            case .deferred:
                print("购买延迟: \(transaction.payment.productIdentifier)")
                handleDeferredTransaction(transaction)
                
            @unknown default:
                print("未知交易状态")
            }
        }
    }
    
    private func handlePurchasedTransaction(_ transaction: SKPaymentTransaction) {
        // 验证收据
        if let receiptData = getReceiptData() {
            print("购买成功，产品ID: \(transaction.payment.productIdentifier)，交易ID: \(transaction.transactionIdentifier ?? "")")
            
            // 缓存交易，等待外部确认
            let transactionId = transaction.transactionIdentifier ?? ""
            if !transactionId.isEmpty {
                pendingTransactions[transactionId] = transaction
            }
            
            // 创建购买结果
            let result = PurchaseResult(
                productIdentifier: transaction.payment.productIdentifier,
                transactionIdentifier: transactionId,
                receiptData: receiptData,
                userID: currentUserID ?? ""
            )
            
            notifyDelegatesSuccess(result)
        } else {
            notifyDelegatesFailure(PurchaseError.receiptValidationFailed)
            finishTransaction(transaction) // 收据验证失败时直接finish
        }
        
        resetTransactionState()
    }
    
    private func handleFailedTransaction(_ transaction: SKPaymentTransaction) {
        if let error = transaction.error {
            print("购买失败: \(error.localizedDescription)")
            
            let skError = error as? SKError
            let purchaseError: PurchaseError
            
            switch skError?.code {
            case .paymentCancelled:
                purchaseError = .userCancelled
            case .paymentNotAllowed:
                purchaseError = .paymentNotAllowed
            case .paymentInvalid:
                purchaseError = .paymentInvalid
            default:
                purchaseError = .unknown(error.localizedDescription)
            }
            
            notifyDelegatesFailure(purchaseError)
        } else {
            notifyDelegatesFailure(PurchaseError.unknown("未知错误"))
        }
        
        finishTransaction(transaction)
        resetTransactionState()
    }
    
    private func handleRestoredTransaction(_ transaction: SKPaymentTransaction) {
        print("恢复购买成功，产品ID: \(transaction.payment.productIdentifier)")
        
        finishTransaction(transaction)
    }
    
    private func handleDeferredTransaction(_ transaction: SKPaymentTransaction) {
        print("购买被延迟，等待批准")
        
        notifyDelegatesFailure(PurchaseError.paymentDeferred)
        resetTransactionState()
    }
    
    private func getReceiptData() -> String? {
        guard let receiptURL = Bundle.main.appStoreReceiptURL,
              let receiptData = try? Data(contentsOf: receiptURL) else {
            return nil
        }
        return receiptData.base64EncodedString()
    }
    
    public func paymentQueue(_ queue: SKPaymentQueue, restoreCompletedTransactionsFailedWithError error: Error) {
        print("恢复购买失败: \(error.localizedDescription)")
    }
    
    public func paymentQueueRestoreCompletedTransactionsFinished(_ queue: SKPaymentQueue) {
        print("恢复购买完成")
    }
}
