//: Promises playground

import UIKit
import PlaygroundSupport

enum Result<Value> {
    case value(Value)
    case error(Error)
}

class Future<Value> {
    fileprivate var result: Result<Value>? {
        // Observe whenever a result is assigned, and report it
        didSet { result.map(report) }
    }
    private lazy var callbacks = [(Result<Value>) -> Void]()
    
    func observe(with callback: @escaping (Result<Value>) -> Void) {
        callbacks.append(callback)
        
        // If a result has already been set, call the callback directly
        result.map(callback)
    }
    
    private func report(result: Result<Value>) {
        for callback in callbacks {
            callback(result)
        }
    }
}

extension Future {
    func chained<NextValue>(with closure: @escaping (Value) throws -> Future<NextValue>) -> Future<NextValue> {
        // Start by constructing a "wrapper" promise that will be
        // returned from this method
        let promise = Promise<NextValue>()
        
        // Observe the current future
        observe { result in
            switch result {
            case .value(let value):
                do {
                    // Attempt to construct a new future given
                    // the value from the first one
                    let future = try closure(value)
                    
                    // Observe the "nested" future, and once it
                    // completes, resolve/reject the "wrapper" future
                    future.observe { result in
                        switch result {
                        case .value(let value):
                            promise.resolve(with: value)
                        case .error(let error):
                            promise.reject(with: error)
                        }
                    }
                } catch {
                    promise.reject(with: error)
                }
            case .error(let error):
                promise.reject(with: error)
            }
        }
        
        return promise
    }
}

extension Future {
    func transformed<NextValue>(with closure: @escaping (Value) throws -> NextValue) -> Future<NextValue> {
        return chained { value in
            return try Promise(value: closure(value))
        }
    }
}

class Promise<Value>: Future<Value> {
    init(value: Value? = nil) {
        super.init()
        
        // If the value was already known at the time the promise
        // was constructed, we can report the value directly
        result = value.map(Result.value)
    }
    
    func resolve(with value: Value) {
        result = .value(value)
    }
    
    func reject(with error: Error) {
        result = .error(error)
    }
}

// MARK: Implementations

extension URLSession {
    func request(url: URL) -> Future<Data> {

        let promise = Promise<Data>()
        
        let task = dataTask(with: url) { data, _, error in
            
            if let error = error {
                promise.reject(with: error)
            } else {
                promise.resolve(with: data ?? Data())
            }
        }
        
        task.resume()
        
        return promise
    }
}

extension Future where Value: Savable {
    func saved(in database: Database) -> Future<Value> {
        return chained { user in
            let promise = Promise<Value>()
            
            database.save(user) {
                promise.resolve(with: user)
            }
            
            return promise
        }
    }
}

extension Future where Value == Data {
    func parse<NewValue: Decodable>(with: NewValue.Type) -> Future<NewValue> {
        return chained { data in
            
            let promise = Promise<NewValue>()
            
            let decoder = JSONDecoder()
            do {
                let response = try decoder.decode(NewValue.self, from: data)
                promise.resolve(with: response)
            } catch(let error) {
               promise.reject(with: error)
            }
            
            return promise
        }
    }
}

// MARK: Models

public struct Response: Codable {
    let message: String
}

// MARK: Mocks

protocol Savable {
    func save()
}

extension Response: Savable {
    func save() {
        print("saving: \(self)")
    }
}

class Database {
    func save(_ value: Savable, with callback: @escaping () -> Void) {
        value.save()
        callback()
    }
}

// MARK: Run

let url = URL(string: "http://www.mocky.io/v2/59a819bd1000009c0d8375c8")!

let database = Database()

URLSession.shared.request(url: url)
    .parse(with: Response.self)
    .saved(in: database)
    .observe { result in
    
    switch result {
        
    case .value(let response):
        print("response: \(response)")
        
    case .error(let error):
        print(error)
        
    }
}


PlaygroundPage.current.needsIndefiniteExecution = true
