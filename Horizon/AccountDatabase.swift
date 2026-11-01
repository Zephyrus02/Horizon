//
//  AccountDatabase.swift
//  Horizon
//
//  Created by Horizon on 29/10/26.
//

import Foundation
import SQLite3

final class AccountDatabase: @unchecked Sendable {
    static let shared = AccountDatabase()

    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "horizon.database.queue", qos: .userInitiated)
    let dbPath: String

    init(dbPath: String? = nil) {
        if let customPath = dbPath {
            self.dbPath = customPath
        } else {
            let appSupport = (("~/Library/Application Support/Horizon" as NSString).expandingTildeInPath)
            try? FileManager.default.createDirectory(atPath: appSupport, withIntermediateDirectories: true)
            self.dbPath = (appSupport as NSString).appendingPathComponent("horizon.db")
        }

        openDatabase()
        createTables()
    }

    deinit {
        if let db = db {
            sqlite3_close(db)
        }
    }

    /// Closes the connection. Later calls become harmless no-ops (SQLite reports MISUSE).
    /// Needed when the backing file is about to be deleted while this object is still alive.
    func close() {
        queue.sync {
            if let handle = db {
                sqlite3_close(handle)
                db = nil
            }
        }
    }

    private func openDatabase() {
        if sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) != SQLITE_OK {
            print("Error opening database at \(dbPath): \(String(cString: sqlite3_errmsg(db)))")
        }
    }

    private func createTables() {
        let sql = """
        CREATE TABLE IF NOT EXISTS accounts (
            id TEXT PRIMARY KEY,
            remote_name TEXT NOT NULL UNIQUE,
            display_name TEXT NOT NULL,
            provider TEXT NOT NULL,
            mount_path TEXT NOT NULL,
            is_connected INTEGER NOT NULL DEFAULT 0,
            auto_connect INTEGER NOT NULL DEFAULT 1,
            created_at REAL NOT NULL,
            account_email TEXT
        );
        """

        queue.sync {
            var errMsg: UnsafeMutablePointer<CChar>?
            if sqlite3_exec(db, sql, nil, nil, &errMsg) != SQLITE_OK {
                if let errMsg = errMsg {
                    print("Error creating accounts table: \(String(cString: errMsg))")
                    sqlite3_free(errMsg)
                }
            }
        }
    }

    // MARK: - CRUD Operations

    func getAllAccounts() -> [RemoteAccount] {
        return queue.sync(execute: { () -> [RemoteAccount] in
            var accounts: [RemoteAccount] = []
            let sql = "SELECT id, remote_name, display_name, provider, mount_path, is_connected, auto_connect, created_at, account_email FROM accounts ORDER BY created_at ASC;"
            var stmt: OpaquePointer?

            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                while sqlite3_step(stmt) == SQLITE_ROW {
                    let id = String(cString: sqlite3_column_text(stmt, 0))
                    let remoteName = String(cString: sqlite3_column_text(stmt, 1))
                    let displayName = String(cString: sqlite3_column_text(stmt, 2))
                    let provider = String(cString: sqlite3_column_text(stmt, 3))
                    let mountPath = String(cString: sqlite3_column_text(stmt, 4))
                    let isConnected = sqlite3_column_int(stmt, 5) != 0
                    let autoConnect = sqlite3_column_int(stmt, 6) != 0
                    let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 7))

                    var accountEmail: String? = nil
                    if let emailPtr = sqlite3_column_text(stmt, 8) {
                        accountEmail = String(cString: emailPtr)
                    }

                    let account = RemoteAccount(
                        id: id,
                        name: remoteName,
                        displayName: displayName,
                        provider: provider,
                        accountName: nil,
                        accountEmail: accountEmail,
                        mountPath: mountPath,
                        isConnected: isConnected,
                        autoConnect: autoConnect,
                        createdAt: createdAt
                    )
                    accounts.append(account)
                }
            }
            sqlite3_finalize(stmt)
            return accounts
        })
    }

    func saveAccount(_ account: RemoteAccount) {
        queue.sync {
            let sql = """
            INSERT INTO accounts (id, remote_name, display_name, provider, mount_path, is_connected, auto_connect, created_at, account_email)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                remote_name = excluded.remote_name,
                display_name = excluded.display_name,
                provider = excluded.provider,
                mount_path = excluded.mount_path,
                is_connected = excluded.is_connected,
                auto_connect = excluded.auto_connect,
                account_email = excluded.account_email;
            """
            var stmt: OpaquePointer?

            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, (account.id as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 2, (account.name as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 3, (account.displayName as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 4, (account.provider as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 5, (account.mountPath as NSString).utf8String, -1, nil)
                sqlite3_bind_int(stmt, 6, account.isConnected ? 1 : 0)
                sqlite3_bind_int(stmt, 7, account.autoConnect ? 1 : 0)
                sqlite3_bind_double(stmt, 8, account.createdAt.timeIntervalSince1970)

                if let email = account.accountEmail {
                    sqlite3_bind_text(stmt, 9, (email as NSString).utf8String, -1, nil)
                } else {
                    sqlite3_bind_null(stmt, 9)
                }

                if sqlite3_step(stmt) != SQLITE_DONE {
                    print("Error saving account to SQLite: \(String(cString: sqlite3_errmsg(db)))")
                }
            }
            sqlite3_finalize(stmt)
        }
    }

    func updateConnectionStatus(id: String, isConnected: Bool) {
        queue.sync {
            let sql = "UPDATE accounts SET is_connected = ? WHERE id = ?;"
            var stmt: OpaquePointer?

            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_int(stmt, 1, isConnected ? 1 : 0)
                sqlite3_bind_text(stmt, 2, (id as NSString).utf8String, -1, nil)
                _ = sqlite3_step(stmt)
            }
            sqlite3_finalize(stmt)
        }
    }

    func deleteAccount(id: String) {
        queue.sync {
            let sql = "DELETE FROM accounts WHERE id = ?;"
            var stmt: OpaquePointer?

            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, (id as NSString).utf8String, -1, nil)
                _ = sqlite3_step(stmt)
            }
            sqlite3_finalize(stmt)
        }
    }

    func deleteAccountByRemoteName(_ remoteName: String) {
        queue.sync {
            let sql = "DELETE FROM accounts WHERE remote_name = ?;"
            var stmt: OpaquePointer?

            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, (remoteName as NSString).utf8String, -1, nil)
                _ = sqlite3_step(stmt)
            }
            sqlite3_finalize(stmt)
        }
    }
}
