import Async
import Dispatch
import Fluent
import Foundation

extension Benchmarker where Database.Connection: TransactionSupporting {
    /// The actual benchmark.
    fileprivate func _benchmark(on conn: Database.Connection) throws {
        // create
        let tanner = User<Database>(name: "Tanner", age: 23)
        try test(tanner.save(on: conn))

        do {
            try conn.transaction { conn in
                var future = Future<Void>(())
                
                /// create 100 users
                for i in 1...100 {
                    let user = User<Database>(name: "User \(i)", age: i)
                    
                    future = future.then {
                        user.save(on: conn)
                    }
                }
                
                return future.then {
                    // count users
                    return conn.query(User<Database>.self).count().then { count -> Future<Void> in
                        if count != 101 {
                            self.fail("count should be 101")
                        }
                        
                        throw "rollback"
                    }
                }
            }.blockingAwait()

            fail("transaction must fail")
        } catch {
            // good
        }

        if try test(conn.query(User<Database>.self).count()) != 1 {
            fail("count must have been restored to one")
        }
    }

    /// Benchmark fluent transactions.
    public func benchmarkTransactions() throws {
        let worker = DispatchQueue(label: "codes.vapor.fluent.benchmark.models")
        let conn = try test(database.makeConnection(on: worker))
        try _benchmark(on: conn)
    }
}

extension Benchmarker where Database.Connection: TransactionSupporting & SchemaSupporting {
    /// Benchmark fluent transactions.
    /// The schema will be prepared first.
    public func benchmarkTransactions_withSchema() throws {
        let worker = DispatchQueue(label: "codes.vapor.fluent.benchmark.models")
        let conn = try test(database.makeConnection(on: worker))
        try test(UserMigration<Database>.prepare(on: conn))
        try _benchmark(on: conn)
    }
}


