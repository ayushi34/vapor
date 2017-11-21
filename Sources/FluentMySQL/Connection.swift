import Async
import Core
import SQL
import FluentSQL
import MySQL
import Fluent

public final class MySQLSerializer: SQLSerializer {
    public init () {}
}

public final class DatabaseConnection: Connection, JoinSupporting {
    let logger: MySQLLogger?
    public let connection: MySQLConnection
    
    init(connection: MySQLConnection, logger: MySQLLogger?) {
        self.connection = connection
        self.logger = logger
    }
    
    public func execute<I, D>(query: DatabaseQuery, into stream: I) where I : ClosableStream, I : InputStream, D : Decodable, D == I.Input {
        /// convert fluent query to sql query
        var (dataQuery, binds) = query.makeDataQuery()
        
        if let model = query.data {
            let encoder = CodingPathKeyPreEncoder()
            
            do {
                dataQuery.columns += try encoder.keys(for: model).flatMap { keys in
                    guard let key = keys.first else {
                        return nil
                    }
                    
                    return DataColumn(name: key)
                }
            } catch {
                stream.errorStream?(error)
                stream.close()
                return
            }
        }
        
        /// create sqlite query from string
        let sqlString = MySQLSerializer().serialize(data: dataQuery)
        
        _ = self.logger?.log(query: sqlString)
        
        connection.withPreparation(statement: sqlString) { context -> Future<Void> in
            do {
                let bound = try context.bind { binding in
                    try binding.withEncoder { encoder in
                        if let model = query.data {
                            try model.encode(to: encoder)
                        } else {
                            for bind in binds {
                                try bind.encodable.encode(to: encoder)
                            }
                        }
                    }
                }
                
                let future = try bound.execute()
                    
                future.do {
                    stream.close()
                }.catch { error in
                    stream.errorStream?(error)
                    stream.close()
                }
                
                return future
            } catch {
                stream.errorStream?(error)
                stream.close()
                return Future(error: error)
            }
        }.catch { error in
            stream.errorStream?(error)
            stream.close()
        }
    }
    
//    /// ReferenceSupporting.enableReferences
//    public func enableReferences() -> Future<Void> {
//        return self.administrativeQuery("PRAGMA foreign_keys = ON;")
//    }
//
//    /// ReferenceSupporting.disableReferences
//    public func disableReferences() -> Future<Void> {
//        return self.administrativeQuery("PRAGMA foreign_keys = OFF;")
//    }
    
    public var lastAutoincrementID: Int? {
        return nil
    }
}

