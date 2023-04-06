//
//  Error.swift
//  llama
//
//  Created by Alex Rozanski on 05/04/2023.
//

import Foundation
import llamaObjCxx

public struct LlamaError {
  public typealias Code = _LlamaErrorCode
  public static let Domain = _LlamaErrorDomain

  private init() {}
}