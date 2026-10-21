
export type Json = string | number | boolean | null | { [key: string]: Json | undefined } | Json[]

export type Database = {
  
  "app": {
          Tables: {
            [_ in never]: never
          }
          Views: {
            [_ in never]: never
          }
          Functions: {
            "accept_dispatch":
{ Args: { "p_shipment_id": string }; Returns: undefined
                           },
"account_normal_side":
{ Args: { "p_type": Database["public"]['Enums']["account_type"] }; Returns: string
                           },
"add_sku_uom":
{ Args: { "p_pieces_per_uom": number,"p_sku_id": string,"p_uom_code": string }; Returns: undefined
                           },
"apply_bps":
{ Args: { "p_amount_kobo": number,"p_bps": number,"p_mode"?: string }; Returns: number
                           },
"apply_push_sale":
{ Args: { "p_accuracy_m": number,"p_agent_user_id": string,"p_idempotency_key": string,"p_lat": number,"p_lines": Json,"p_lng": number,"p_retailer_org_id": string,"p_shipment_id": string,"p_skip_geofence"?: boolean }; Returns: Json
                           },
"apply_sync_event":
{ Args: { "p_dev": Omit<Database["public"]['Tables']["agent_devices"]['Row'], Database["public"]['Tables']["agent_devices"]['ComputedFields']>,"p_event": Json }; Returns: Json
                           },
"can_manage_branch":
{ Args: { "p_branch_id": string }; Returns: boolean
                           },
"can_operate_warehouse":
{ Args: { "p_roles": (Database["public"]['Enums']["member_role"])[],"p_warehouse_id": string }; Returns: boolean
                           },
"cancel_order":
{ Args: { "p_order_id": string,"p_reason": string }; Returns: undefined
                           },
"check_geofence":
{ Args: { "p_accuracy_m": number,"p_distributor_id": string,"p_lat": number,"p_lng": number,"p_retailer_org_id": string }; Returns: {
              "distance_m": number,"max_accuracy_m": number,"ok": boolean,"radius_m": number,"reason": string
            }[]
                           },
"check_journals_balanced":
{ Args: Record<PropertyKey, never>; Returns: {
              "book_org_id": string,"entry_count": number,"journal_id": string,"net": number
            }[]
                           },
"check_money_projection":
{ Args: Record<PropertyKey, never>; Returns: {
              "account_id": string,"ledger_balance": number,"projected_balance": number
            }[]
                           },
"check_stock_conservation":
{ Args: Record<PropertyKey, never>; Returns: {
              "expected": number,"on_hand_total": number,"sku_id": string
            }[]
                           },
"check_stock_projection":
{ Args: Record<PropertyKey, never>; Returns: {
              "ledger_on_hand": number,"ledger_reserved": number,"location_id": string,"projected_on_hand": number,"projected_reserved": number,"sku_id": string
            }[]
                           },
"close_shipment":
{ Args: { "p_shipment_id": string }; Returns: undefined
                           },
"complete_push_handover":
{ Args: { "p_shipment_id": string }; Returns: undefined
                           },
"complete_push_return":
{ Args: { "p_payload_hash": string,"p_shipment_id": string }; Returns: string
                           },
"confirm_delivery":
{ Args: { "p_order_id": string }; Returns: undefined
                           },
"confirm_return":
{ Args: { "p_shipment_id": string }; Returns: string
                           },
"create_batch":
{ Args: { "p_order_ids": (string)[],"p_warehouse_id": string }; Returns: string
                           },
"create_branch":
{ Args: { "p_name": string,"p_org_id": string }; Returns: string
                           },
"create_brand":
{ Args: { "p_manufacturer_id": string,"p_name": string }; Returns: string
                           },
"create_sku":
{ Args: { "p_brand_id": string,"p_carton_pieces"?: number,"p_code": string,"p_manufacturer_id": string,"p_name": string }; Returns: string
                           },
"create_territory":
{ Args: { "p_boundary"?: Json,"p_branch_id": string,"p_name": string }; Returns: string
                           },
"create_transfer":
{ Args: { "p_from_warehouse_id": string,"p_lines": Json,"p_to_warehouse_id": string }; Returns: string
                           },
"create_warehouse":
{ Args: { "p_branch_id": string,"p_lat": number,"p_lng": number,"p_name": string }; Returns: string
                           },
"current_price_kobo":
{ Args: { "p_distributor_id": string,"p_sku_id": string,"p_uom_code": string }; Returns: number
                           },
"current_user_id":
{ Args: Record<PropertyKey, never>; Returns: string
                           },
"decide_adjustment":
{ Args: { "p_approve": boolean,"p_reason"?: string,"p_request_id": string }; Returns: undefined
                           },
"decide_customer":
{ Args: { "p_approve": boolean,"p_reason"?: string,"p_relationship_id": string,"p_territory_id"?: string }; Returns: undefined
                           },
"decide_join_request":
{ Args: { "p_approve": boolean,"p_branch_id"?: string,"p_reason"?: string,"p_request_id": string,"p_territory_id"?: string }; Returns: undefined
                           },
"decide_split":
{ Args: { "p_choice": string,"p_order_id": string }; Returns: undefined
                           },
"decide_stock_request":
{ Args: { "p_approve": boolean,"p_approved"?: Json,"p_reason"?: string,"p_request_id": string }; Returns: string
                           },
"decline_dispatch":
{ Args: { "p_reason": string,"p_shipment_id": string }; Returns: undefined
                           },
"dispatch_batch":
{ Args: { "p_batch_id": string,"p_carrier_user_id": string }; Returns: string
                           },
"dispatch_transfer":
{ Args: { "p_transfer_id": string }; Returns: undefined
                           },
"dispute_delivery":
{ Args: { "p_order_id": string,"p_reason": string }; Returns: string
                           },
"ensure_account":
{ Args: { "p_account_type": Database["public"]['Enums']["account_type"],"p_book_org_id": string,"p_counterparty_org_id"?: string,"p_counterparty_user_id"?: string,"p_holder_org_id"?: string,"p_provider"?: string }; Returns: string
                           },
"evaluate_geofence":
{ Args: { "p_accuracy_m": number,"p_distributor_id": string,"p_lat": number,"p_lng": number,"p_retailer_org_id": string }; Returns: {
              "distance_m": number,"max_accuracy_m": number,"ok": boolean,"radius_m": number,"reason": string
            }[]
                           },
"has_role":
{ Args: { "p_org_id": string,"p_roles": (Database["public"]['Enums']["member_role"])[] }; Returns: boolean
                           },
"is_platform_admin":
{ Args: Record<PropertyKey, never>; Returns: boolean
                           },
"issue_otp_code":
{ Args: { "p_challenge_id": string }; Returns: {
              "code": string,"phone_e164": string,"purpose": string
            }[]
                           },
"kyc_level":
{ Args: { "p_org_id": string }; Returns: number
                           },
"lines_to_pieces":
{ Args: { "p_lines": Json }; Returns: {
              "line_no": number,"qty_pieces": number,"sku_id": string,"uom_code": string,"uom_qty": number
            }[]
                           },
"make_point":
{ Args: { "p_lat": number,"p_lng": number }; Returns: unknown
                           },
"mark_batch_packed":
{ Args: { "p_batch_id": string }; Returns: undefined
                           },
"my_branch_ids":
{ Args: { "p_roles": (Database["public"]['Enums']["member_role"])[] }; Returns: (string)[]
                           },
"my_carrier_location_ids":
{ Args: Record<PropertyKey, never>; Returns: (string)[]
                           },
"my_org_ids":
{ Args: Record<PropertyKey, never>; Returns: (string)[]
                           },
"my_org_ids_with_role":
{ Args: { "p_roles": (Database["public"]['Enums']["member_role"])[] }; Returns: (string)[]
                           },
"onboard_organisation":
{ Args: { "p_admin_user_id": string,"p_kind": Database["public"]['Enums']["org_kind"],"p_name": string,"p_slug": string }; Returns: string
                           },
"open_otp_challenge":
{ Args: { "p_initiator": string,"p_payload_hash"?: string,"p_purpose": string,"p_recipient": string,"p_subject_id": string,"p_subject_kind": string }; Returns: string
                           },
"piece_price_kobo":
{ Args: { "p_distributor_id": string,"p_sku_id": string }; Returns: number
                           },
"place_order":
{ Args: { "p_distributor_id": string,"p_idempotency_key": string,"p_lines": Json,"p_retailer_org_id": string }; Returns: Json
                           },
"post_journal":
{ Args: { "p_entries": Json,"p_idempotency_key": string,"p_journal_type": string,"p_memo"?: string,"p_ref_id"?: string,"p_ref_kind"?: string,"p_reverses_journal_id"?: string }; Returns: string
                           },
"post_stock_movement":
{ Args: { "p_group_id": string,"p_idempotency_key"?: string,"p_location_id": string,"p_qty": number,"p_reason"?: string,"p_ref_id"?: string,"p_ref_kind"?: string,"p_sign"?: number,"p_sku_id": string,"p_type": Database["public"]['Enums']["movement_type"] }; Returns: string
                           },
"publish_price_list":
{ Args: { "p_distributor_id": string,"p_effective_from": string,"p_items": Json,"p_name": string }; Returns: string
                           },
"receive_transfer":
{ Args: { "p_lines": Json,"p_transfer_id": string }; Returns: string
                           },
"record_delivery":
{ Args: { "p_accuracy_m": number,"p_idempotency_key": string,"p_lat": number,"p_lines": Json,"p_lng": number,"p_order_id": string,"p_photo_path": string,"p_recipient_name": string,"p_shipment_id": string }; Returns: Json
                           },
"record_kyc_result":
{ Args: { "p_id_hash": string,"p_id_type": string,"p_org_id": string,"p_outcome": string,"p_provider": string,"p_provider_ref": string,"p_subject_user_id": string }; Returns: Json
                           },
"record_push_sale":
{ Args: { "p_accuracy_m": number,"p_idempotency_key": string,"p_lat": number,"p_lines": Json,"p_lng": number,"p_retailer_org_id": string,"p_shipment_id": string }; Returns: Json
                           },
"record_receipt":
{ Args: { "p_idempotency_key": string,"p_lines": Json,"p_reference": string,"p_warehouse_id": string }; Returns: string
                           },
"refresh_order_status":
{ Args: { "p_order_id": string }; Returns: undefined
                           },
"register_device":
{ Args: { "p_device_id": string,"p_org_id": string }; Returns: number
                           },
"register_retailer":
{ Args: { "p_accuracy_m": number,"p_business_name": string,"p_distributor_id": string,"p_full_name": string,"p_lat": number,"p_lng": number,"p_phone_e164": string }; Returns: string
                           },
"registration_directory":
{ Args: Record<PropertyKey, never>; Returns: {
              "id": string,"name": string
            }[]
                           },
"request_adjustment":
{ Args: { "p_qty_delta": number,"p_reason": string,"p_sku_id": string,"p_warehouse_id": string }; Returns: string
                           },
"request_distributor":
{ Args: { "p_distributor_id": string,"p_retailer_org_id": string }; Returns: string
                           },
"request_stock":
{ Args: { "p_lines": Json,"p_note"?: string,"p_warehouse_id": string }; Returns: string
                           },
"request_to_join":
{ Args: { "p_distributor_id": string,"p_full_name": string,"p_note"?: string,"p_phone_e164": string,"p_role": Database["public"]['Enums']["member_role"] }; Returns: string
                           },
"require_branch_manager":
{ Args: { "p_branch_id": string }; Returns: string
                           },
"require_role":
{ Args: { "p_org_id": string,"p_roles": (Database["public"]['Enums']["member_role"])[] }; Returns: string
                           },
"require_user":
{ Args: Record<PropertyKey, never>; Returns: string
                           },
"require_warehouse_operator":
{ Args: { "p_roles": (Database["public"]['Enums']["member_role"])[],"p_warehouse_id": string }; Returns: string
                           },
"reserve_allocations":
{ Args: { "p_allocations": Json,"p_order_id": string }; Returns: undefined
                           },
"reserve_order":
{ Args: { "p_order_id": string,"p_warehouse_id": string }; Returns: undefined
                           },
"resolve_transfer_shortage":
{ Args: { "p_reason": string,"p_transfer_id": string }; Returns: undefined
                           },
"resolve_variance":
{ Args: { "p_case_id": string,"p_decision": string,"p_note": string }; Returns: string
                           },
"review_accept_into_variance":
{ Args: { "p_item_id": string,"p_note": string }; Returns: Json
                           },
"review_dismiss":
{ Args: { "p_item_id": string,"p_reason": string }; Returns: undefined
                           },
"round_div":
{ Args: { "p_den": number,"p_mode"?: string,"p_num": number }; Returns: number
                           },
"route_and_reserve":
{ Args: { "p_order_id": string }; Returns: string
                           },
"set_sku_active":
{ Args: { "p_active": boolean,"p_sku_id": string }; Returns: undefined
                           },
"set_warehouse_active":
{ Args: { "p_active": boolean,"p_warehouse_id": string }; Returns: undefined
                           },
"settle_carrier":
{ Args: { "p_shipment_id": string }; Returns: string
                           },
"start_handover":
{ Args: { "p_shipment_id": string }; Returns: string
                           },
"start_push_return":
{ Args: { "p_lines": Json,"p_shipment_id": string }; Returns: string
                           },
"start_return":
{ Args: { "p_lines": Json,"p_shipment_id": string }; Returns: undefined
                           },
"suggest_territory":
{ Args: { "p_distributor_id": string,"p_point": unknown }; Returns: string
                           },
"sync_agent_events":
{ Args: { "p_device_id": string,"p_events": Json }; Returns: Json
                           },
"update_distributor_settings":
{ Args: { "p_geofence_max_accuracy_m": number,"p_geofence_radius_m": number,"p_org_id": string,"p_split_threshold_m": number }; Returns: undefined
                           },
"upsert_my_profile":
{ Args: { "p_full_name": string,"p_phone_e164": string }; Returns: undefined
                           },
"verify_otp":
{ Args: { "p_challenge_id": string,"p_code": string }; Returns: Json
                           },
"visible_account_ids":
{ Args: Record<PropertyKey, never>; Returns: (string)[]
                           },
"visible_distributor_ids":
{ Args: Record<PropertyKey, never>; Returns: (string)[]
                           },
"visible_location_ids":
{ Args: Record<PropertyKey, never>; Returns: (string)[]
                           },
"visible_manufacturer_ids":
{ Args: Record<PropertyKey, never>; Returns: (string)[]
                           },
"visible_order_ids":
{ Args: Record<PropertyKey, never>; Returns: (string)[]
                           },
"visible_retailer_ids":
{ Args: Record<PropertyKey, never>; Returns: (string)[]
                           },
"visible_shipment_ids":
{ Args: Record<PropertyKey, never>; Returns: (string)[]
                           },
"visible_user_ids":
{ Args: Record<PropertyKey, never>; Returns: (string)[]
                           },
"visible_warehouse_ids":
{ Args: Record<PropertyKey, never>; Returns: (string)[]
                           },
"warehouse_location":
{ Args: { "p_warehouse_id": string }; Returns: string
                           }
          }
          Enums: {
            [_ in never]: never
          }
          CompositeTypes: {
            [_ in never]: never
          }
        },"public": {
          Tables: {
            "account_balances": {
                  Row: {
                    "account_id": string,"account_type": Database["public"]['Enums']["account_type"],"balance_kobo": number,"book_org_id": string,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "account_id": string,"account_type": Database["public"]['Enums']["account_type"],"balance_kobo"?: number,"book_org_id": string,"updated_at"?: string
                  }
                  Update: {
                    "account_id"?: string,"account_type"?: Database["public"]['Enums']["account_type"],"balance_kobo"?: number,"book_org_id"?: string,"updated_at"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "account_balances_account_id_fkey"
      columns: ["account_id"]
isOneToOne: true
      referencedRelation: "accounts"
      referencedColumns: ["id"]
    }
                  ]
                },"accounts": {
                  Row: {
                    "account_type": Database["public"]['Enums']["account_type"],"book_kind": Database["public"]['Enums']["org_kind"],"book_org_id": string,"counterparty_org_id": string | null,"counterparty_user_id": string | null,"created_at": string,"holder_org_id": string | null,"id": string,"provider": string | null
                  }
                  ComputedFields: never
                  Insert: {
                    "account_type": Database["public"]['Enums']["account_type"],"book_kind": Database["public"]['Enums']["org_kind"],"book_org_id": string,"counterparty_org_id"?: string | null,"counterparty_user_id"?: string | null,"created_at"?: string,"holder_org_id"?: string | null,"id"?: string,"provider"?: string | null
                  }
                  Update: {
                    "account_type"?: Database["public"]['Enums']["account_type"],"book_kind"?: Database["public"]['Enums']["org_kind"],"book_org_id"?: string,"counterparty_org_id"?: string | null,"counterparty_user_id"?: string | null,"created_at"?: string,"holder_org_id"?: string | null,"id"?: string,"provider"?: string | null
                  }
                  Relationships: [
                    {
      foreignKeyName: "accounts_book_org_id_book_kind_fkey"
      columns: ["book_org_id","book_kind"]
isOneToOne: false
      referencedRelation: "organisations"
      referencedColumns: ["id","kind"]
    },{
      foreignKeyName: "accounts_book_org_id_book_kind_fkey"
      columns: ["book_org_id","book_kind"]
isOneToOne: false
      referencedRelation: "v_organisations"
      referencedColumns: ["id","kind"]
    },{
      foreignKeyName: "accounts_counterparty_org_id_fkey"
      columns: ["counterparty_org_id"]
isOneToOne: false
      referencedRelation: "organisations"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "accounts_counterparty_org_id_fkey"
      columns: ["counterparty_org_id"]
isOneToOne: false
      referencedRelation: "v_organisations"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "accounts_counterparty_user_id_fkey"
      columns: ["counterparty_user_id"]
isOneToOne: false
      referencedRelation: "profiles"
      referencedColumns: ["user_id"]
    },{
      foreignKeyName: "accounts_holder_org_id_fkey"
      columns: ["holder_org_id"]
isOneToOne: false
      referencedRelation: "organisations"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "accounts_holder_org_id_fkey"
      columns: ["holder_org_id"]
isOneToOne: false
      referencedRelation: "v_organisations"
      referencedColumns: ["id"]
    }
                  ]
                },"adjustment_requests": {
                  Row: {
                    "created_at": string,"decided_at": string | null,"decided_by": string | null,"decision_reason": string | null,"id": string,"location_id": string,"org_id": string,"qty_delta": number,"reason": string,"requested_by": string,"sku_id": string,"status": Database["public"]['Enums']["record_status"]
                  }
                  ComputedFields: never
                  Insert: {
                    "created_at"?: string,"decided_at"?: string | null,"decided_by"?: string | null,"decision_reason"?: string | null,"id"?: string,"location_id": string,"org_id": string,"qty_delta": number,"reason": string,"requested_by": string,"sku_id": string,"status"?: Database["public"]['Enums']["record_status"]
                  }
                  Update: {
                    "created_at"?: string,"decided_at"?: string | null,"decided_by"?: string | null,"decision_reason"?: string | null,"id"?: string,"location_id"?: string,"org_id"?: string,"qty_delta"?: number,"reason"?: string,"requested_by"?: string,"sku_id"?: string,"status"?: Database["public"]['Enums']["record_status"]
                  }
                  Relationships: [
                    {
      foreignKeyName: "adjustment_requests_decided_by_fkey"
      columns: ["decided_by"]
isOneToOne: false
      referencedRelation: "profiles"
      referencedColumns: ["user_id"]
    },{
      foreignKeyName: "adjustment_requests_location_id_fkey"
      columns: ["location_id"]
isOneToOne: false
      referencedRelation: "stock_locations"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "adjustment_requests_org_id_fkey"
      columns: ["org_id"]
isOneToOne: false
      referencedRelation: "organisations"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "adjustment_requests_org_id_fkey"
      columns: ["org_id"]
isOneToOne: false
      referencedRelation: "v_organisations"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "adjustment_requests_requested_by_fkey"
      columns: ["requested_by"]
isOneToOne: false
      referencedRelation: "profiles"
      referencedColumns: ["user_id"]
    },{
      foreignKeyName: "adjustment_requests_sku_id_fkey"
      columns: ["sku_id"]
isOneToOne: false
      referencedRelation: "skus"
      referencedColumns: ["id"]
    }
                  ]
                },"agent_devices": {
                  Row: {
                    "device_id": string,"last_seq": number,"last_sync_at": string | null,"org_id": string,"registered_at": string,"user_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "device_id": string,"last_seq"?: number,"last_sync_at"?: string | null,"org_id": string,"registered_at"?: string,"user_id": string
                  }
                  Update: {
                    "device_id"?: string,"last_seq"?: number,"last_sync_at"?: string | null,"org_id"?: string,"registered_at"?: string,"user_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "agent_devices_org_id_fkey"
      columns: ["org_id"]
isOneToOne: false
      referencedRelation: "organisations"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "agent_devices_org_id_fkey"
      columns: ["org_id"]
isOneToOne: false
      referencedRelation: "v_organisations"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "agent_devices_user_id_fkey"
      columns: ["user_id"]
isOneToOne: false
      referencedRelation: "profiles"
      referencedColumns: ["user_id"]
    }
                  ]
                },"agent_visits": {
                  Row: {
                    "agent_user_id": string,"distance_m": number | null,"event_id": string,"geofence_ok": boolean,"geofence_reason": string,"id": string,"org_id": string,"recorded_at": string,"retailer_org_id": string,"visited_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "agent_user_id": string,"distance_m"?: number | null,"event_id": string,"geofence_ok": boolean,"geofence_reason": string,"id"?: string,"org_id": string,"recorded_at"?: string,"retailer_org_id": string,"visited_at": string
                  }
                  Update: {
                    "agent_user_id"?: string,"distance_m"?: number | null,"event_id"?: string,"geofence_ok"?: boolean,"geofence_reason"?: string,"id"?: string,"org_id"?: string,"recorded_at"?: string,"retailer_org_id"?: string,"visited_at"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "agent_visits_agent_user_id_fkey"
      columns: ["agent_user_id"]
isOneToOne: false
      referencedRelation: "profiles"
      referencedColumns: ["user_id"]
    },{
      foreignKeyName: "agent_visits_event_id_fkey"
      columns: ["event_id"]
isOneToOne: true
      referencedRelation: "sync_events"
      referencedColumns: ["event_id"]
    },{
      foreignKeyName: "agent_visits_org_id_fkey"
      columns: ["org_id"]
isOneToOne: false
      referencedRelation: "organisations"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "agent_visits_org_id_fkey"
      columns: ["org_id"]
isOneToOne: false
      referencedRelation: "v_organisations"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "agent_visits_retailer_org_id_fkey"
      columns: ["retailer_org_id"]
isOneToOne: false
      referencedRelation: "organisations"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "agent_visits_retailer_org_id_fkey"
      columns: ["retailer_org_id"]
isOneToOne: false
      referencedRelation: "v_organisations"
      referencedColumns: ["id"]
    }
                  ]
                },"batches": {
                  Row: {
                    "created_at": string,"created_by": string,"id": string,"org_id": string,"packed_at": string | null,"packed_by": string | null,"status": string,"warehouse_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "created_at"?: string,"created_by": string,"id"?: string,"org_id": string,"packed_at"?: string | null,"packed_by"?: string | null,"status"?: string,"warehouse_id": string
                  }
                  Update: {
                    "created_at"?: string,"created_by"?: string,"id"?: string,"org_id"?: string,"packed_at"?: string | null,"packed_by"?: string | null,"status"?: string,"warehouse_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "batches_created_by_fkey"
      columns: ["created_by"]
isOneToOne: false
      referencedRelation: "profiles"
      referencedColumns: ["user_id"]
    },{
      foreignKeyName: "batches_org_id_fkey"
      columns: ["org_id"]
isOneToOne: false
      referencedRelation: "organisations"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "batches_org_id_fkey"
      columns: ["org_id"]
isOneToOne: false
      referencedRelation: "v_organisations"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "batches_packed_by_fkey"
      columns: ["packed_by"]
isOneToOne: false
      referencedRelation: "profiles"
      referencedColumns: ["user_id"]
    },{
      foreignKeyName: "batches_warehouse_id_fkey"
      columns: ["warehouse_id"]
isOneToOne: false
      referencedRelation: "v_warehouses"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "batches_warehouse_id_fkey"
      columns: ["warehouse_id"]
isOneToOne: false
      referencedRelation: "warehouses"
      referencedColumns: ["id"]
    }
                  ]
                },"branches": {
                  Row: {
                    "created_at": string,"id": string,"name": string,"org_id": string,"org_kind": Database["public"]['Enums']["org_kind"]
                  }
                  ComputedFields: never
                  Insert: {
                    "created_at"?: string,"id"?: string,"name": string,"org_id": string,"org_kind"?: Database["public"]['Enums']["org_kind"]
                  }
                  Update: {
                    "created_at"?: string,"id"?: string,"name"?: string,"org_id"?: string,"org_kind"?: Database["public"]['Enums']["org_kind"]
                  }
                  Relationships: [
                    {
      foreignKeyName: "branches_org_id_org_kind_fkey"
      columns: ["org_id","org_kind"]
isOneToOne: false
      referencedRelation: "organisations"
      referencedColumns: ["id","kind"]
    },{
      foreignKeyName: "branches_org_id_org_kind_fkey"
      columns: ["org_id","org_kind"]
isOneToOne: false
      referencedRelation: "v_organisations"
      referencedColumns: ["id","kind"]
    }
                  ]
                },"brands": {
                  Row: {
                    "created_at": string,"id": string,"manufacturer_kind": Database["public"]['Enums']["org_kind"],"manufacturer_org_id": string,"name": string
                  }
                  ComputedFields: never
                  Insert: {
                    "created_at"?: string,"id"?: string,"manufacturer_kind"?: Database["public"]['Enums']["org_kind"],"manufacturer_org_id": string,"name": string
                  }
                  Update: {
                    "created_at"?: string,"id"?: string,"manufacturer_kind"?: Database["public"]['Enums']["org_kind"],"manufacturer_org_id"?: string,"name"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "brands_manufacturer_org_id_manufacturer_kind_fkey"
      columns: ["manufacturer_org_id","manufacturer_kind"]
isOneToOne: false
      referencedRelation: "organisations"
      referencedColumns: ["id","kind"]
    },{
      foreignKeyName: "brands_manufacturer_org_id_manufacturer_kind_fkey"
      columns: ["manufacturer_org_id","manufacturer_kind"]
isOneToOne: false
      referencedRelation: "v_organisations"
      referencedColumns: ["id","kind"]
    }
                  ]
                },"customer_relationships": {
                  Row: {
                    "created_at": string,"credit_limit_kobo": number,"decided_at": string | null,"decided_by": string | null,"decision_reason": string | null,"distributor_kind": Database["public"]['Enums']["org_kind"],"distributor_org_id": string,"id": string,"retailer_kind": Database["public"]['Enums']["org_kind"],"retailer_org_id": string,"status": Database["public"]['Enums']["record_status"],"territory_id": string,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "created_at"?: string,"credit_limit_kobo"?: number,"decided_at"?: string | null,"decided_by"?: string | null,"decision_reason"?: string | null,"distributor_kind"?: Database["public"]['Enums']["org_kind"],"distributor_org_id": string,"id"?: string,"retailer_kind"?: Database["public"]['Enums']["org_kind"],"retailer_org_id": string,"status"?: Database["public"]['Enums']["record_status"],"territory_id": string,"updated_at"?: string
                  }
                  Update: {
                    "created_at"?: string,"credit_limit_kobo"?: number,"decided_at"?: string | null,"decided_by"?: string | null,"decision_reason"?: string | null,"distributor_kind"?: Database["public"]['Enums']["org_kind"],"distributor_org_id"?: string,"id"?: string,"retailer_kind"?: Database["public"]['Enums']["org_kind"],"retailer_org_id"?: string,"status"?: Database["public"]['Enums']["record_status"],"territory_id"?: string,"updated_at"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "customer_relationships_decided_by_fkey"
      columns: ["decided_by"]
isOneToOne: false
      referencedRelation: "profiles"
      referencedColumns: ["user_id"]
    },{
      foreignKeyName: "customer_relationships_distributor_org_id_distributor_kind_fkey"
      columns: ["distributor_org_id","distributor_kind"]
isOneToOne: false
      referencedRelation: "organisations"
      referencedColumns: ["id","kind"]
    },{
      foreignKeyName: "customer_relationships_distributor_org_id_distributor_kind_fkey"
      columns: ["distributor_org_id","distributor_kind"]
isOneToOne: false
      referencedRelation: "v_organisations"
      referencedColumns: ["id","kind"]
    },{
      foreignKeyName: "customer_relationships_retailer_org_id_retailer_kind_fkey"
      columns: ["retailer_org_id","retailer_kind"]
isOneToOne: false
      referencedRelation: "organisations"
      referencedColumns: ["id","kind"]
    },{
      foreignKeyName: "customer_relationships_retailer_org_id_retailer_kind_fkey"
      columns: ["retailer_org_id","retailer_kind"]
isOneToOne: false
      referencedRelation: "v_organisations"
      referencedColumns: ["id","kind"]
    },{
      foreignKeyName: "customer_relationships_territory_id_distributor_org_id_fkey"
      columns: ["territory_id","distributor_org_id"]
isOneToOne: false
      referencedRelation: "territories"
      referencedColumns: ["id","org_id"]
    },{
      foreignKeyName: "customer_relationships_territory_id_distributor_org_id_fkey"
      columns: ["territory_id","distributor_org_id"]
isOneToOne: false
      referencedRelation: "v_territories"
      referencedColumns: ["id","org_id"]
    }
                  ]
                },"deliveries": {
                  Row: {
                    "accuracy_m": number,"distance_m": number | null,"geofence_ok": boolean,"geofence_reason": string,"id": string,"idempotency_key": string,"invoiced_kobo": number,"journal_id": string | null,"lat": number,"lng": number,"order_id": string,"photo_path": string,"recipient_name": string,"recorded_at": string,"recorded_by": string,"shipment_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "accuracy_m": number,"distance_m"?: number | null,"geofence_ok": boolean,"geofence_reason": string,"id"?: string,"idempotency_key": string,"invoiced_kobo"?: number,"journal_id"?: string | null,"lat": number,"lng": number,"order_id": string,"photo_path": string,"recipient_name": string,"recorded_at"?: string,"recorded_by": string,"shipment_id": string
                  }
                  Update: {
                    "accuracy_m"?: number,"distance_m"?: number | null,"geofence_ok"?: boolean,"geofence_reason"?: string,"id"?: string,"idempotency_key"?: string,"invoiced_kobo"?: number,"journal_id"?: string | null,"lat"?: number,"lng"?: number,"order_id"?: string,"photo_path"?: string,"recipient_name"?: string,"recorded_at"?: string,"recorded_by"?: string,"shipment_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "deliveries_journal_id_fkey"
      columns: ["journal_id"]
isOneToOne: false
      referencedRelation: "journals"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "deliveries_order_id_fkey"
      columns: ["order_id"]
isOneToOne: false
      referencedRelation: "orders"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "deliveries_order_id_fkey"
      columns: ["order_id"]
isOneToOne: false
      referencedRelation: "v_orders"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "deliveries_recorded_by_fkey"
      columns: ["recorded_by"]
isOneToOne: false
      referencedRelation: "profiles"
      referencedColumns: ["user_id"]
    },{
      foreignKeyName: "deliveries_shipment_id_fkey"
      columns: ["shipment_id"]
isOneToOne: false
      referencedRelation: "shipments"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "deliveries_shipment_id_fkey"
      columns: ["shipment_id"]
isOneToOne: false
      referencedRelation: "v_shipment_reconciliation"
      referencedColumns: ["shipment_id"]
    }
                  ]
                },"delivery_lines": {
                  Row: {
                    "allocation_id": string,"damaged": number,"delivered": number,"delivery_id": string,"id": string,"missing": number,"refused": number
                  }
                  ComputedFields: never
                  Insert: {
                    "allocation_id": string,"damaged": number,"delivered": number,"delivery_id": string,"id"?: string,"missing": number,"refused": number
                  }
                  Update: {
                    "allocation_id"?: string,"damaged"?: number,"delivered"?: number,"delivery_id"?: string,"id"?: string,"missing"?: number,"refused"?: number
                  }
                  Relationships: [
                    {
      foreignKeyName: "delivery_lines_allocation_id_fkey"
      columns: ["allocation_id"]
isOneToOne: true
      referencedRelation: "order_allocations"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "delivery_lines_delivery_id_fkey"
      columns: ["delivery_id"]
isOneToOne: false
      referencedRelation: "deliveries"
      referencedColumns: ["id"]
    }
                  ]
                },"join_requests": {
                  Row: {
                    "created_at": string,"decided_at": string | null,"decided_by": string | null,"decision_reason": string | null,"id": string,"note": string | null,"org_id": string,"org_kind": Database["public"]['Enums']["org_kind"],"requested_role": Database["public"]['Enums']["member_role"],"status": Database["public"]['Enums']["record_status"],"updated_at": string,"user_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "created_at"?: string,"decided_at"?: string | null,"decided_by"?: string | null,"decision_reason"?: string | null,"id"?: string,"note"?: string | null,"org_id": string,"org_kind"?: Database["public"]['Enums']["org_kind"],"requested_role": Database["public"]['Enums']["member_role"],"status"?: Database["public"]['Enums']["record_status"],"updated_at"?: string,"user_id": string
                  }
                  Update: {
                    "created_at"?: string,"decided_at"?: string | null,"decided_by"?: string | null,"decision_reason"?: string | null,"id"?: string,"note"?: string | null,"org_id"?: string,"org_kind"?: Database["public"]['Enums']["org_kind"],"requested_role"?: Database["public"]['Enums']["member_role"],"status"?: Database["public"]['Enums']["record_status"],"updated_at"?: string,"user_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "join_requests_decided_by_fkey"
      columns: ["decided_by"]
isOneToOne: false
      referencedRelation: "profiles"
      referencedColumns: ["user_id"]
    },{
      foreignKeyName: "join_requests_org_id_org_kind_fkey"
      columns: ["org_id","org_kind"]
isOneToOne: false
      referencedRelation: "organisations"
      referencedColumns: ["id","kind"]
    },{
      foreignKeyName: "join_requests_org_id_org_kind_fkey"
      columns: ["org_id","org_kind"]
isOneToOne: false
      referencedRelation: "v_organisations"
      referencedColumns: ["id","kind"]
    },{
      foreignKeyName: "join_requests_user_id_fkey"
      columns: ["user_id"]
isOneToOne: false
      referencedRelation: "profiles"
      referencedColumns: ["user_id"]
    }
                  ]
                },"journals": {
                  Row: {
                    "id": string,"idempotency_key": string,"journal_type": string,"memo": string | null,"posted_at": string,"posted_by": string | null,"ref_id": string | null,"ref_kind": string | null,"request_hash": string,"reverses_journal_id": string | null
                  }
                  ComputedFields: never
                  Insert: {
                    "id"?: string,"idempotency_key": string,"journal_type": string,"memo"?: string | null,"posted_at"?: string,"posted_by"?: string | null,"ref_id"?: string | null,"ref_kind"?: string | null,"request_hash": string,"reverses_journal_id"?: string | null
                  }
                  Update: {
                    "id"?: string,"idempotency_key"?: string,"journal_type"?: string,"memo"?: string | null,"posted_at"?: string,"posted_by"?: string | null,"ref_id"?: string | null,"ref_kind"?: string | null,"request_hash"?: string,"reverses_journal_id"?: string | null
                  }
                  Relationships: [
                    {
      foreignKeyName: "journals_reverses_journal_id_fkey"
      columns: ["reverses_journal_id"]
isOneToOne: false
      referencedRelation: "journals"
      referencedColumns: ["id"]
    }
                  ]
                },"kyc_checks": {
                  Row: {
                    "checked_at": string,"id": string,"id_hash": string,"id_type": string,"org_id": string,"outcome": string,"provider": string,"provider_ref": string,"seq": number,"subject_user_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "checked_at"?: string,"id"?: string,"id_hash": string,"id_type": string,"org_id": string,"outcome": string,"provider": string,"provider_ref": string,"seq"?: never,"subject_user_id": string
                  }
                  Update: {
                    "checked_at"?: string,"id"?: string,"id_hash"?: string,"id_type"?: string,"org_id"?: string,"outcome"?: string,"provider"?: string,"provider_ref"?: string,"seq"?: never,"subject_user_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "kyc_checks_org_id_fkey"
      columns: ["org_id"]
isOneToOne: false
      referencedRelation: "organisations"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "kyc_checks_org_id_fkey"
      columns: ["org_id"]
isOneToOne: false
      referencedRelation: "v_organisations"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "kyc_checks_subject_user_id_fkey"
      columns: ["subject_user_id"]
isOneToOne: false
      referencedRelation: "profiles"
      referencedColumns: ["user_id"]
    }
                  ]
                },"ledger_entries": {
                  Row: {
                    "account_id": string,"amount_kobo": number,"book_org_id": string,"created_at": string,"id": string,"journal_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "account_id": string,"amount_kobo": number,"book_org_id": string,"created_at"?: string,"id"?: string,"journal_id": string
                  }
                  Update: {
                    "account_id"?: string,"amount_kobo"?: number,"book_org_id"?: string,"created_at"?: string,"id"?: string,"journal_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "ledger_entries_account_id_fkey"
      columns: ["account_id"]
isOneToOne: false
      referencedRelation: "accounts"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "ledger_entries_journal_id_fkey"
      columns: ["journal_id"]
isOneToOne: false
      referencedRelation: "journals"
      referencedColumns: ["id"]
    }
                  ]
                },"memberships": {
                  Row: {
                    "branch_id": string | null,"created_at": string,"id": string,"org_id": string,"org_kind": Database["public"]['Enums']["org_kind"],"role": Database["public"]['Enums']["member_role"],"status": Database["public"]['Enums']["record_status"],"territory_id": string | null,"updated_at": string,"user_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "branch_id"?: string | null,"created_at"?: string,"id"?: string,"org_id": string,"org_kind": Database["public"]['Enums']["org_kind"],"role": Database["public"]['Enums']["member_role"],"status"?: Database["public"]['Enums']["record_status"],"territory_id"?: string | null,"updated_at"?: string,"user_id": string
                  }
                  Update: {
                    "branch_id"?: string | null,"created_at"?: string,"id"?: string,"org_id"?: string,"org_kind"?: Database["public"]['Enums']["org_kind"],"role"?: Database["public"]['Enums']["member_role"],"status"?: Database["public"]['Enums']["record_status"],"territory_id"?: string | null,"updated_at"?: string,"user_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "memberships_branch_id_org_id_fkey"
      columns: ["branch_id","org_id"]
isOneToOne: false
      referencedRelation: "branches"
      referencedColumns: ["id","org_id"]
    },{
      foreignKeyName: "memberships_org_id_org_kind_fkey"
      columns: ["org_id","org_kind"]
isOneToOne: false
      referencedRelation: "organisations"
      referencedColumns: ["id","kind"]
    },{
      foreignKeyName: "memberships_org_id_org_kind_fkey"
      columns: ["org_id","org_kind"]
isOneToOne: false
      referencedRelation: "v_organisations"
      referencedColumns: ["id","kind"]
    },{
      foreignKeyName: "memberships_territory_id_branch_id_fkey"
      columns: ["territory_id","branch_id"]
isOneToOne: false
      referencedRelation: "territories"
      referencedColumns: ["id","branch_id"]
    },{
      foreignKeyName: "memberships_territory_id_branch_id_fkey"
      columns: ["territory_id","branch_id"]
isOneToOne: false
      referencedRelation: "v_territories"
      referencedColumns: ["id","branch_id"]
    },{
      foreignKeyName: "memberships_user_id_fkey"
      columns: ["user_id"]
isOneToOne: false
      referencedRelation: "profiles"
      referencedColumns: ["user_id"]
    }
                  ]
                },"order_allocations": {
                  Row: {
                    "batch_id": string | null,"created_at": string,"id": string,"order_id": string,"order_line_id": string,"qty_pieces": number,"sku_id": string,"status": string,"warehouse_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "batch_id"?: string | null,"created_at"?: string,"id"?: string,"order_id": string,"order_line_id": string,"qty_pieces": number,"sku_id": string,"status"?: string,"warehouse_id": string
                  }
                  Update: {
                    "batch_id"?: string | null,"created_at"?: string,"id"?: string,"order_id"?: string,"order_line_id"?: string,"qty_pieces"?: number,"sku_id"?: string,"status"?: string,"warehouse_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "order_allocations_batch_fk"
      columns: ["batch_id"]
isOneToOne: false
      referencedRelation: "batches"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "order_allocations_order_id_fkey"
      columns: ["order_id"]
isOneToOne: false
      referencedRelation: "orders"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "order_allocations_order_id_fkey"
      columns: ["order_id"]
isOneToOne: false
      referencedRelation: "v_orders"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "order_allocations_order_line_id_fkey"
      columns: ["order_line_id"]
isOneToOne: false
      referencedRelation: "order_lines"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "order_allocations_sku_id_fkey"
      columns: ["sku_id"]
isOneToOne: false
      referencedRelation: "skus"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "order_allocations_warehouse_id_fkey"
      columns: ["warehouse_id"]
isOneToOne: false
      referencedRelation: "v_warehouses"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "order_allocations_warehouse_id_fkey"
      columns: ["warehouse_id"]
isOneToOne: false
      referencedRelation: "warehouses"
      referencedColumns: ["id"]
    }
                  ]
                },"order_disputes": {
                  Row: {
                    "created_at": string,"id": string,"order_id": string,"raised_by": string,"reason": string,"status": string
                  }
                  ComputedFields: never
                  Insert: {
                    "created_at"?: string,"id"?: string,"order_id": string,"raised_by": string,"reason": string,"status"?: string
                  }
                  Update: {
                    "created_at"?: string,"id"?: string,"order_id"?: string,"raised_by"?: string,"reason"?: string,"status"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "order_disputes_order_id_fkey"
      columns: ["order_id"]
isOneToOne: false
      referencedRelation: "orders"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "order_disputes_order_id_fkey"
      columns: ["order_id"]
isOneToOne: false
      referencedRelation: "v_orders"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "order_disputes_raised_by_fkey"
      columns: ["raised_by"]
isOneToOne: false
      referencedRelation: "profiles"
      referencedColumns: ["user_id"]
    }
                  ]
                },"order_lines": {
                  Row: {
                    "created_at": string,"id": string,"line_amount_kobo": number | null,"order_id": string,"qty_pieces": number,"sku_id": string,"uom_code": string,"uom_price_kobo": number,"uom_qty": number,"warehouse_id": string | null
                  }
                  ComputedFields: never
                  Insert: {
                    "created_at"?: string,"id"?: string,"line_amount_kobo"?: never,"order_id": string,"qty_pieces": number,"sku_id": string,"uom_code": string,"uom_price_kobo": number,"uom_qty": number,"warehouse_id"?: string | null
                  }
                  Update: {
                    "created_at"?: string,"id"?: string,"line_amount_kobo"?: never,"order_id"?: string,"qty_pieces"?: number,"sku_id"?: string,"uom_code"?: string,"uom_price_kobo"?: number,"uom_qty"?: number,"warehouse_id"?: string | null
                  }
                  Relationships: [
                    {
      foreignKeyName: "order_lines_order_id_fkey"
      columns: ["order_id"]
isOneToOne: false
      referencedRelation: "orders"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "order_lines_order_id_fkey"
      columns: ["order_id"]
isOneToOne: false
      referencedRelation: "v_orders"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "order_lines_sku_id_uom_code_fkey"
      columns: ["sku_id","uom_code"]
isOneToOne: false
      referencedRelation: "sku_uom"
      referencedColumns: ["sku_id","uom_code"]
    },{
      foreignKeyName: "order_lines_warehouse_id_fkey"
      columns: ["warehouse_id"]
isOneToOne: false
      referencedRelation: "v_warehouses"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "order_lines_warehouse_id_fkey"
      columns: ["warehouse_id"]
isOneToOne: false
      referencedRelation: "warehouses"
      referencedColumns: ["id"]
    }
                  ]
                },"orders": {
                  Row: {
                    "cancelled_reason": string | null,"confirmed_at": string | null,"created_at": string,"distributor_org_id": string,"id": string,"idempotency_key": string | null,"order_kind": Database["public"]['Enums']["order_kind"],"placed_by_role": Database["public"]['Enums']["member_role"] | null,"placed_by_user_id": string | null,"retailer_org_id": string,"routing_decision": Json | null,"routing_reason": string | null,"status": Database["public"]['Enums']["order_status"],"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "cancelled_reason"?: string | null,"confirmed_at"?: string | null,"created_at"?: string,"distributor_org_id": string,"id"?: string,"idempotency_key"?: string | null,"order_kind"?: Database["public"]['Enums']["order_kind"],"placed_by_role"?: Database["public"]['Enums']["member_role"] | null,"placed_by_user_id"?: string | null,"retailer_org_id": string,"routing_decision"?: Json | null,"routing_reason"?: string | null,"status"?: Database["public"]['Enums']["order_status"],"updated_at"?: string
                  }
                  Update: {
                    "cancelled_reason"?: string | null,"confirmed_at"?: string | null,"created_at"?: string,"distributor_org_id"?: string,"id"?: string,"idempotency_key"?: string | null,"order_kind"?: Database["public"]['Enums']["order_kind"],"placed_by_role"?: Database["public"]['Enums']["member_role"] | null,"placed_by_user_id"?: string | null,"retailer_org_id"?: string,"routing_decision"?: Json | null,"routing_reason"?: string | null,"status"?: Database["public"]['Enums']["order_status"],"updated_at"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "orders_distributor_org_id_retailer_org_id_fkey"
      columns: ["distributor_org_id","retailer_org_id"]
isOneToOne: false
      referencedRelation: "customer_relationships"
      referencedColumns: ["distributor_org_id","retailer_org_id"]
    },{
      foreignKeyName: "orders_placed_by_user_id_fkey"
      columns: ["placed_by_user_id"]
isOneToOne: false
      referencedRelation: "profiles"
      referencedColumns: ["user_id"]
    }
                  ]
                },"organisations": {
                  Row: {
                    "created_at": string,"geofence_max_accuracy_m": number | null,"geofence_radius_m": number | null,"id": string,"kind": Database["public"]['Enums']["org_kind"],"location": unknown,"location_accuracy_m": number | null,"name": string,"slug": string,"split_threshold_m": number | null,"status": Database["public"]['Enums']["record_status"],"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "created_at"?: string,"geofence_max_accuracy_m"?: number | null,"geofence_radius_m"?: number | null,"id"?: string,"kind": Database["public"]['Enums']["org_kind"],"location"?: unknown,"location_accuracy_m"?: number | null,"name": string,"slug": string,"split_threshold_m"?: number | null,"status"?: Database["public"]['Enums']["record_status"],"updated_at"?: string
                  }
                  Update: {
                    "created_at"?: string,"geofence_max_accuracy_m"?: number | null,"geofence_radius_m"?: number | null,"id"?: string,"kind"?: Database["public"]['Enums']["org_kind"],"location"?: unknown,"location_accuracy_m"?: number | null,"name"?: string,"slug"?: string,"split_threshold_m"?: number | null,"status"?: Database["public"]['Enums']["record_status"],"updated_at"?: string
                  }
                  Relationships: [
                    
                  ]
                },"price_list_items": {
                  Row: {
                    "price_kobo": number,"price_list_id": string,"sku_id": string,"uom_code": string
                  }
                  ComputedFields: never
                  Insert: {
                    "price_kobo": number,"price_list_id": string,"sku_id": string,"uom_code": string
                  }
                  Update: {
                    "price_kobo"?: number,"price_list_id"?: string,"sku_id"?: string,"uom_code"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "price_list_items_price_list_id_fkey"
      columns: ["price_list_id"]
isOneToOne: false
      referencedRelation: "price_lists"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "price_list_items_price_list_id_fkey"
      columns: ["price_list_id"]
isOneToOne: false
      referencedRelation: "v_current_prices"
      referencedColumns: ["price_list_id"]
    },{
      foreignKeyName: "price_list_items_sku_id_uom_code_fkey"
      columns: ["sku_id","uom_code"]
isOneToOne: false
      referencedRelation: "sku_uom"
      referencedColumns: ["sku_id","uom_code"]
    }
                  ]
                },"price_lists": {
                  Row: {
                    "created_at": string,"distributor_kind": Database["public"]['Enums']["org_kind"],"distributor_org_id": string,"effective_from": string,"id": string,"name": string
                  }
                  ComputedFields: never
                  Insert: {
                    "created_at"?: string,"distributor_kind"?: Database["public"]['Enums']["org_kind"],"distributor_org_id": string,"effective_from": string,"id"?: string,"name": string
                  }
                  Update: {
                    "created_at"?: string,"distributor_kind"?: Database["public"]['Enums']["org_kind"],"distributor_org_id"?: string,"effective_from"?: string,"id"?: string,"name"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "price_lists_distributor_org_id_distributor_kind_fkey"
      columns: ["distributor_org_id","distributor_kind"]
isOneToOne: false
      referencedRelation: "organisations"
      referencedColumns: ["id","kind"]
    },{
      foreignKeyName: "price_lists_distributor_org_id_distributor_kind_fkey"
      columns: ["distributor_org_id","distributor_kind"]
isOneToOne: false
      referencedRelation: "v_organisations"
      referencedColumns: ["id","kind"]
    }
                  ]
                },"profiles": {
                  Row: {
                    "created_at": string,"full_name": string,"phone_e164": string | null,"updated_at": string,"user_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "created_at"?: string,"full_name": string,"phone_e164"?: string | null,"updated_at"?: string,"user_id": string
                  }
                  Update: {
                    "created_at"?: string,"full_name"?: string,"phone_e164"?: string | null,"updated_at"?: string,"user_id"?: string
                  }
                  Relationships: [
                    
                  ]
                },"push_sale_lines": {
                  Row: {
                    "amount_kobo": number | null,"id": string,"qty_pieces": number,"sale_id": string,"sku_id": string,"unit_price_kobo": number
                  }
                  ComputedFields: never
                  Insert: {
                    "amount_kobo"?: never,"id"?: string,"qty_pieces": number,"sale_id": string,"sku_id": string,"unit_price_kobo": number
                  }
                  Update: {
                    "amount_kobo"?: never,"id"?: string,"qty_pieces"?: number,"sale_id"?: string,"sku_id"?: string,"unit_price_kobo"?: number
                  }
                  Relationships: [
                    {
      foreignKeyName: "push_sale_lines_sale_id_fkey"
      columns: ["sale_id"]
isOneToOne: false
      referencedRelation: "push_sales"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "push_sale_lines_sku_id_fkey"
      columns: ["sku_id"]
isOneToOne: false
      referencedRelation: "skus"
      referencedColumns: ["id"]
    }
                  ]
                },"push_sales": {
                  Row: {
                    "accuracy_m": number,"agent_user_id": string,"created_at": string,"distance_m": number | null,"id": string,"idempotency_key": string,"journal_id": string | null,"lat": number,"lng": number,"retailer_org_id": string,"shipment_id": string,"total_kobo": number
                  }
                  ComputedFields: never
                  Insert: {
                    "accuracy_m": number,"agent_user_id": string,"created_at"?: string,"distance_m"?: number | null,"id"?: string,"idempotency_key": string,"journal_id"?: string | null,"lat": number,"lng": number,"retailer_org_id": string,"shipment_id": string,"total_kobo": number
                  }
                  Update: {
                    "accuracy_m"?: number,"agent_user_id"?: string,"created_at"?: string,"distance_m"?: number | null,"id"?: string,"idempotency_key"?: string,"journal_id"?: string | null,"lat"?: number,"lng"?: number,"retailer_org_id"?: string,"shipment_id"?: string,"total_kobo"?: number
                  }
                  Relationships: [
                    {
      foreignKeyName: "push_sales_agent_user_id_fkey"
      columns: ["agent_user_id"]
isOneToOne: false
      referencedRelation: "profiles"
      referencedColumns: ["user_id"]
    },{
      foreignKeyName: "push_sales_journal_id_fkey"
      columns: ["journal_id"]
isOneToOne: false
      referencedRelation: "journals"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "push_sales_retailer_org_id_fkey"
      columns: ["retailer_org_id"]
isOneToOne: false
      referencedRelation: "organisations"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "push_sales_retailer_org_id_fkey"
      columns: ["retailer_org_id"]
isOneToOne: false
      referencedRelation: "v_organisations"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "push_sales_shipment_id_fkey"
      columns: ["shipment_id"]
isOneToOne: false
      referencedRelation: "shipments"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "push_sales_shipment_id_fkey"
      columns: ["shipment_id"]
isOneToOne: false
      referencedRelation: "v_shipment_reconciliation"
      referencedColumns: ["shipment_id"]
    }
                  ]
                },"receipts": {
                  Row: {
                    "created_at": string,"id": string,"idempotency_key": string,"org_id": string,"received_by": string,"reference": string,"warehouse_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "created_at"?: string,"id"?: string,"idempotency_key": string,"org_id": string,"received_by": string,"reference": string,"warehouse_id": string
                  }
                  Update: {
                    "created_at"?: string,"id"?: string,"idempotency_key"?: string,"org_id"?: string,"received_by"?: string,"reference"?: string,"warehouse_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "receipts_org_id_fkey"
      columns: ["org_id"]
isOneToOne: false
      referencedRelation: "organisations"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "receipts_org_id_fkey"
      columns: ["org_id"]
isOneToOne: false
      referencedRelation: "v_organisations"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "receipts_received_by_fkey"
      columns: ["received_by"]
isOneToOne: false
      referencedRelation: "profiles"
      referencedColumns: ["user_id"]
    },{
      foreignKeyName: "receipts_warehouse_id_fkey"
      columns: ["warehouse_id"]
isOneToOne: false
      referencedRelation: "v_warehouses"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "receipts_warehouse_id_fkey"
      columns: ["warehouse_id"]
isOneToOne: false
      referencedRelation: "warehouses"
      referencedColumns: ["id"]
    }
                  ]
                },"review_items": {
                  Row: {
                    "agent_user_id": string,"created_at": string,"decided_at": string | null,"decided_by": string | null,"decision_note": string | null,"event_id": string,"id": string,"org_id": string,"reason": string,"status": string
                  }
                  ComputedFields: never
                  Insert: {
                    "agent_user_id": string,"created_at"?: string,"decided_at"?: string | null,"decided_by"?: string | null,"decision_note"?: string | null,"event_id": string,"id"?: string,"org_id": string,"reason": string,"status"?: string
                  }
                  Update: {
                    "agent_user_id"?: string,"created_at"?: string,"decided_at"?: string | null,"decided_by"?: string | null,"decision_note"?: string | null,"event_id"?: string,"id"?: string,"org_id"?: string,"reason"?: string,"status"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "review_items_agent_user_id_fkey"
      columns: ["agent_user_id"]
isOneToOne: false
      referencedRelation: "profiles"
      referencedColumns: ["user_id"]
    },{
      foreignKeyName: "review_items_decided_by_fkey"
      columns: ["decided_by"]
isOneToOne: false
      referencedRelation: "profiles"
      referencedColumns: ["user_id"]
    },{
      foreignKeyName: "review_items_event_id_fkey"
      columns: ["event_id"]
isOneToOne: true
      referencedRelation: "sync_events"
      referencedColumns: ["event_id"]
    },{
      foreignKeyName: "review_items_org_id_fkey"
      columns: ["org_id"]
isOneToOne: false
      referencedRelation: "organisations"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "review_items_org_id_fkey"
      columns: ["org_id"]
isOneToOne: false
      referencedRelation: "v_organisations"
      referencedColumns: ["id"]
    }
                  ]
                },"shipment_lines": {
                  Row: {
                    "id": string,"qty_pieces": number,"shipment_id": string,"sku_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "id"?: string,"qty_pieces": number,"shipment_id": string,"sku_id": string
                  }
                  Update: {
                    "id"?: string,"qty_pieces"?: number,"shipment_id"?: string,"sku_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "shipment_lines_shipment_id_fkey"
      columns: ["shipment_id"]
isOneToOne: false
      referencedRelation: "shipments"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "shipment_lines_shipment_id_fkey"
      columns: ["shipment_id"]
isOneToOne: false
      referencedRelation: "v_shipment_reconciliation"
      referencedColumns: ["shipment_id"]
    },{
      foreignKeyName: "shipment_lines_sku_id_fkey"
      columns: ["sku_id"]
isOneToOne: false
      referencedRelation: "skus"
      referencedColumns: ["id"]
    }
                  ]
                },"shipment_returns": {
                  Row: {
                    "confirmed_at": string | null,"counted_by": string,"created_at": string,"damaged": number,"id": string,"qty_pieces": number,"shipment_id": string,"sku_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "confirmed_at"?: string | null,"counted_by": string,"created_at"?: string,"damaged"?: number,"id"?: string,"qty_pieces": number,"shipment_id": string,"sku_id": string
                  }
                  Update: {
                    "confirmed_at"?: string | null,"counted_by"?: string,"created_at"?: string,"damaged"?: number,"id"?: string,"qty_pieces"?: number,"shipment_id"?: string,"sku_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "shipment_returns_counted_by_fkey"
      columns: ["counted_by"]
isOneToOne: false
      referencedRelation: "profiles"
      referencedColumns: ["user_id"]
    },{
      foreignKeyName: "shipment_returns_shipment_id_fkey"
      columns: ["shipment_id"]
isOneToOne: false
      referencedRelation: "shipments"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "shipment_returns_shipment_id_fkey"
      columns: ["shipment_id"]
isOneToOne: false
      referencedRelation: "v_shipment_reconciliation"
      referencedColumns: ["shipment_id"]
    },{
      foreignKeyName: "shipment_returns_sku_id_fkey"
      columns: ["sku_id"]
isOneToOne: false
      referencedRelation: "skus"
      referencedColumns: ["id"]
    }
                  ]
                },"shipments": {
                  Row: {
                    "accepted_at": string | null,"batch_id": string | null,"carrier_location_id": string,"closed_at": string | null,"created_at": string,"dispatched_by": string,"id": string,"kind": string,"org_id": string,"status": string,"status_note": string | null,"updated_at": string,"warehouse_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "accepted_at"?: string | null,"batch_id"?: string | null,"carrier_location_id": string,"closed_at"?: string | null,"created_at"?: string,"dispatched_by": string,"id"?: string,"kind": string,"org_id": string,"status"?: string,"status_note"?: string | null,"updated_at"?: string,"warehouse_id": string
                  }
                  Update: {
                    "accepted_at"?: string | null,"batch_id"?: string | null,"carrier_location_id"?: string,"closed_at"?: string | null,"created_at"?: string,"dispatched_by"?: string,"id"?: string,"kind"?: string,"org_id"?: string,"status"?: string,"status_note"?: string | null,"updated_at"?: string,"warehouse_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "shipments_batch_id_fkey"
      columns: ["batch_id"]
isOneToOne: false
      referencedRelation: "batches"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "shipments_carrier_location_id_fkey"
      columns: ["carrier_location_id"]
isOneToOne: false
      referencedRelation: "stock_locations"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "shipments_dispatched_by_fkey"
      columns: ["dispatched_by"]
isOneToOne: false
      referencedRelation: "profiles"
      referencedColumns: ["user_id"]
    },{
      foreignKeyName: "shipments_org_id_fkey"
      columns: ["org_id"]
isOneToOne: false
      referencedRelation: "organisations"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "shipments_org_id_fkey"
      columns: ["org_id"]
isOneToOne: false
      referencedRelation: "v_organisations"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "shipments_warehouse_id_fkey"
      columns: ["warehouse_id"]
isOneToOne: false
      referencedRelation: "v_warehouses"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "shipments_warehouse_id_fkey"
      columns: ["warehouse_id"]
isOneToOne: false
      referencedRelation: "warehouses"
      referencedColumns: ["id"]
    }
                  ]
                },"sku_uom": {
                  Row: {
                    "pieces_per_uom": number,"sku_id": string,"uom_code": string
                  }
                  ComputedFields: never
                  Insert: {
                    "pieces_per_uom": number,"sku_id": string,"uom_code": string
                  }
                  Update: {
                    "pieces_per_uom"?: number,"sku_id"?: string,"uom_code"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "sku_uom_sku_id_fkey"
      columns: ["sku_id"]
isOneToOne: false
      referencedRelation: "skus"
      referencedColumns: ["id"]
    }
                  ]
                },"skus": {
                  Row: {
                    "active": boolean,"brand_id": string,"code": string,"created_at": string,"id": string,"item_class": string,"manufacturer_org_id": string,"name": string,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "active"?: boolean,"brand_id": string,"code": string,"created_at"?: string,"id"?: string,"item_class"?: string,"manufacturer_org_id": string,"name": string,"updated_at"?: string
                  }
                  Update: {
                    "active"?: boolean,"brand_id"?: string,"code"?: string,"created_at"?: string,"id"?: string,"item_class"?: string,"manufacturer_org_id"?: string,"name"?: string,"updated_at"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "skus_brand_id_manufacturer_org_id_fkey"
      columns: ["brand_id","manufacturer_org_id"]
isOneToOne: false
      referencedRelation: "brands"
      referencedColumns: ["id","manufacturer_org_id"]
    }
                  ]
                },"stock_balances": {
                  Row: {
                    "available": number | null,"location_id": string,"location_kind": Database["public"]['Enums']["location_kind"],"on_hand": number,"org_id": string,"reserved": number,"sku_id": string,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "available"?: never,"location_id": string,"location_kind": Database["public"]['Enums']["location_kind"],"on_hand"?: number,"org_id": string,"reserved"?: number,"sku_id": string,"updated_at"?: string
                  }
                  Update: {
                    "available"?: never,"location_id"?: string,"location_kind"?: Database["public"]['Enums']["location_kind"],"on_hand"?: number,"org_id"?: string,"reserved"?: number,"sku_id"?: string,"updated_at"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "stock_balances_location_id_org_id_fkey"
      columns: ["location_id","org_id"]
isOneToOne: false
      referencedRelation: "stock_locations"
      referencedColumns: ["id","org_id"]
    },{
      foreignKeyName: "stock_balances_sku_id_fkey"
      columns: ["sku_id"]
isOneToOne: false
      referencedRelation: "skus"
      referencedColumns: ["id"]
    }
                  ]
                },"stock_locations": {
                  Row: {
                    "created_at": string,"id": string,"kind": Database["public"]['Enums']["location_kind"],"org_id": string,"org_kind": Database["public"]['Enums']["org_kind"],"user_id": string | null,"warehouse_id": string | null
                  }
                  ComputedFields: never
                  Insert: {
                    "created_at"?: string,"id"?: string,"kind": Database["public"]['Enums']["location_kind"],"org_id": string,"org_kind"?: Database["public"]['Enums']["org_kind"],"user_id"?: string | null,"warehouse_id"?: string | null
                  }
                  Update: {
                    "created_at"?: string,"id"?: string,"kind"?: Database["public"]['Enums']["location_kind"],"org_id"?: string,"org_kind"?: Database["public"]['Enums']["org_kind"],"user_id"?: string | null,"warehouse_id"?: string | null
                  }
                  Relationships: [
                    {
      foreignKeyName: "stock_locations_org_id_org_kind_fkey"
      columns: ["org_id","org_kind"]
isOneToOne: false
      referencedRelation: "organisations"
      referencedColumns: ["id","kind"]
    },{
      foreignKeyName: "stock_locations_org_id_org_kind_fkey"
      columns: ["org_id","org_kind"]
isOneToOne: false
      referencedRelation: "v_organisations"
      referencedColumns: ["id","kind"]
    },{
      foreignKeyName: "stock_locations_user_id_fkey"
      columns: ["user_id"]
isOneToOne: false
      referencedRelation: "profiles"
      referencedColumns: ["user_id"]
    },{
      foreignKeyName: "stock_locations_warehouse_id_org_id_fkey"
      columns: ["warehouse_id","org_id"]
isOneToOne: false
      referencedRelation: "v_warehouses"
      referencedColumns: ["id","org_id"]
    },{
      foreignKeyName: "stock_locations_warehouse_id_org_id_fkey"
      columns: ["warehouse_id","org_id"]
isOneToOne: false
      referencedRelation: "warehouses"
      referencedColumns: ["id","org_id"]
    }
                  ]
                },"stock_movements": {
                  Row: {
                    "actor_user_id": string | null,"batch_id": string | null,"expiry_date": string | null,"id": string,"idempotency_key": string | null,"location_id": string,"movement_group_id": string,"movement_type": Database["public"]['Enums']["movement_type"],"occurred_at": string,"on_hand_delta": number,"org_id": string,"qty": number,"reason": string | null,"recorded_at": string,"ref_id": string | null,"ref_kind": string | null,"reserved_delta": number,"sku_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "actor_user_id"?: string | null,"batch_id"?: string | null,"expiry_date"?: string | null,"id"?: string,"idempotency_key"?: string | null,"location_id": string,"movement_group_id": string,"movement_type": Database["public"]['Enums']["movement_type"],"occurred_at"?: string,"on_hand_delta": number,"org_id": string,"qty": number,"reason"?: string | null,"recorded_at"?: string,"ref_id"?: string | null,"ref_kind"?: string | null,"reserved_delta": number,"sku_id": string
                  }
                  Update: {
                    "actor_user_id"?: string | null,"batch_id"?: string | null,"expiry_date"?: string | null,"id"?: string,"idempotency_key"?: string | null,"location_id"?: string,"movement_group_id"?: string,"movement_type"?: Database["public"]['Enums']["movement_type"],"occurred_at"?: string,"on_hand_delta"?: number,"org_id"?: string,"qty"?: number,"reason"?: string | null,"recorded_at"?: string,"ref_id"?: string | null,"ref_kind"?: string | null,"reserved_delta"?: number,"sku_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "stock_movements_location_id_org_id_fkey"
      columns: ["location_id","org_id"]
isOneToOne: false
      referencedRelation: "stock_locations"
      referencedColumns: ["id","org_id"]
    },{
      foreignKeyName: "stock_movements_sku_id_fkey"
      columns: ["sku_id"]
isOneToOne: false
      referencedRelation: "skus"
      referencedColumns: ["id"]
    }
                  ]
                },"stock_request_lines": {
                  Row: {
                    "id": string,"qty_approved": number | null,"qty_pieces": number,"request_id": string,"sku_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "id"?: string,"qty_approved"?: number | null,"qty_pieces": number,"request_id": string,"sku_id": string
                  }
                  Update: {
                    "id"?: string,"qty_approved"?: number | null,"qty_pieces"?: number,"request_id"?: string,"sku_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "stock_request_lines_request_id_fkey"
      columns: ["request_id"]
isOneToOne: false
      referencedRelation: "stock_requests"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "stock_request_lines_sku_id_fkey"
      columns: ["sku_id"]
isOneToOne: false
      referencedRelation: "skus"
      referencedColumns: ["id"]
    }
                  ]
                },"stock_requests": {
                  Row: {
                    "agent_user_id": string,"carrier_location_id": string,"created_at": string,"decided_at": string | null,"decided_by": string | null,"decision_reason": string | null,"id": string,"note": string | null,"org_id": string,"shipment_id": string | null,"status": string,"warehouse_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "agent_user_id": string,"carrier_location_id": string,"created_at"?: string,"decided_at"?: string | null,"decided_by"?: string | null,"decision_reason"?: string | null,"id"?: string,"note"?: string | null,"org_id": string,"shipment_id"?: string | null,"status"?: string,"warehouse_id": string
                  }
                  Update: {
                    "agent_user_id"?: string,"carrier_location_id"?: string,"created_at"?: string,"decided_at"?: string | null,"decided_by"?: string | null,"decision_reason"?: string | null,"id"?: string,"note"?: string | null,"org_id"?: string,"shipment_id"?: string | null,"status"?: string,"warehouse_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "stock_requests_agent_user_id_fkey"
      columns: ["agent_user_id"]
isOneToOne: false
      referencedRelation: "profiles"
      referencedColumns: ["user_id"]
    },{
      foreignKeyName: "stock_requests_carrier_location_id_fkey"
      columns: ["carrier_location_id"]
isOneToOne: false
      referencedRelation: "stock_locations"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "stock_requests_decided_by_fkey"
      columns: ["decided_by"]
isOneToOne: false
      referencedRelation: "profiles"
      referencedColumns: ["user_id"]
    },{
      foreignKeyName: "stock_requests_org_id_fkey"
      columns: ["org_id"]
isOneToOne: false
      referencedRelation: "organisations"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "stock_requests_org_id_fkey"
      columns: ["org_id"]
isOneToOne: false
      referencedRelation: "v_organisations"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "stock_requests_shipment_id_fkey"
      columns: ["shipment_id"]
isOneToOne: false
      referencedRelation: "shipments"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "stock_requests_shipment_id_fkey"
      columns: ["shipment_id"]
isOneToOne: false
      referencedRelation: "v_shipment_reconciliation"
      referencedColumns: ["shipment_id"]
    },{
      foreignKeyName: "stock_requests_warehouse_id_fkey"
      columns: ["warehouse_id"]
isOneToOne: false
      referencedRelation: "v_warehouses"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "stock_requests_warehouse_id_fkey"
      columns: ["warehouse_id"]
isOneToOne: false
      referencedRelation: "warehouses"
      referencedColumns: ["id"]
    }
                  ]
                },"supply_relationships": {
                  Row: {
                    "created_at": string,"distributor_kind": Database["public"]['Enums']["org_kind"],"distributor_org_id": string,"manufacturer_kind": Database["public"]['Enums']["org_kind"],"manufacturer_org_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "created_at"?: string,"distributor_kind"?: Database["public"]['Enums']["org_kind"],"distributor_org_id": string,"manufacturer_kind"?: Database["public"]['Enums']["org_kind"],"manufacturer_org_id": string
                  }
                  Update: {
                    "created_at"?: string,"distributor_kind"?: Database["public"]['Enums']["org_kind"],"distributor_org_id"?: string,"manufacturer_kind"?: Database["public"]['Enums']["org_kind"],"manufacturer_org_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "supply_relationships_distributor_org_id_distributor_kind_fkey"
      columns: ["distributor_org_id","distributor_kind"]
isOneToOne: false
      referencedRelation: "organisations"
      referencedColumns: ["id","kind"]
    },{
      foreignKeyName: "supply_relationships_distributor_org_id_distributor_kind_fkey"
      columns: ["distributor_org_id","distributor_kind"]
isOneToOne: false
      referencedRelation: "v_organisations"
      referencedColumns: ["id","kind"]
    },{
      foreignKeyName: "supply_relationships_manufacturer_org_id_manufacturer_kind_fkey"
      columns: ["manufacturer_org_id","manufacturer_kind"]
isOneToOne: false
      referencedRelation: "organisations"
      referencedColumns: ["id","kind"]
    },{
      foreignKeyName: "supply_relationships_manufacturer_org_id_manufacturer_kind_fkey"
      columns: ["manufacturer_org_id","manufacturer_kind"]
isOneToOne: false
      referencedRelation: "v_organisations"
      referencedColumns: ["id","kind"]
    }
                  ]
                },"sync_events": {
                  Row: {
                    "accuracy_m": number | null,"agent_user_id": string,"client_ts": string | null,"device_id": string,"event_id": string,"lat": number | null,"lng": number | null,"org_id": string,"payload": NonNullable<Json>,"reason": string | null,"recorded_at": string,"result": Json | null,"seq": number,"status": string,"type": string
                  }
                  ComputedFields: never
                  Insert: {
                    "accuracy_m"?: number | null,"agent_user_id": string,"client_ts"?: string | null,"device_id": string,"event_id": string,"lat"?: number | null,"lng"?: number | null,"org_id": string,"payload": NonNullable<Json>,"reason"?: string | null,"recorded_at"?: string,"result"?: Json | null,"seq": number,"status": string,"type": string
                  }
                  Update: {
                    "accuracy_m"?: number | null,"agent_user_id"?: string,"client_ts"?: string | null,"device_id"?: string,"event_id"?: string,"lat"?: number | null,"lng"?: number | null,"org_id"?: string,"payload"?: NonNullable<Json>,"reason"?: string | null,"recorded_at"?: string,"result"?: Json | null,"seq"?: number,"status"?: string,"type"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "sync_events_agent_user_id_fkey"
      columns: ["agent_user_id"]
isOneToOne: false
      referencedRelation: "profiles"
      referencedColumns: ["user_id"]
    },{
      foreignKeyName: "sync_events_device_id_fkey"
      columns: ["device_id"]
isOneToOne: false
      referencedRelation: "agent_devices"
      referencedColumns: ["device_id"]
    },{
      foreignKeyName: "sync_events_org_id_fkey"
      columns: ["org_id"]
isOneToOne: false
      referencedRelation: "organisations"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "sync_events_org_id_fkey"
      columns: ["org_id"]
isOneToOne: false
      referencedRelation: "v_organisations"
      referencedColumns: ["id"]
    }
                  ]
                },"territories": {
                  Row: {
                    "boundary": unknown,"branch_id": string,"created_at": string,"id": string,"name": string,"org_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "boundary"?: unknown,"branch_id": string,"created_at"?: string,"id"?: string,"name": string,"org_id": string
                  }
                  Update: {
                    "boundary"?: unknown,"branch_id"?: string,"created_at"?: string,"id"?: string,"name"?: string,"org_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "territories_branch_id_org_id_fkey"
      columns: ["branch_id","org_id"]
isOneToOne: false
      referencedRelation: "branches"
      referencedColumns: ["id","org_id"]
    }
                  ]
                },"transfer_lines": {
                  Row: {
                    "damaged": number | null,"id": string,"qty_pieces": number,"received": number | null,"sku_id": string,"transfer_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "damaged"?: number | null,"id"?: string,"qty_pieces": number,"received"?: number | null,"sku_id": string,"transfer_id": string
                  }
                  Update: {
                    "damaged"?: number | null,"id"?: string,"qty_pieces"?: number,"received"?: number | null,"sku_id"?: string,"transfer_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "transfer_lines_sku_id_fkey"
      columns: ["sku_id"]
isOneToOne: false
      referencedRelation: "skus"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "transfer_lines_transfer_id_fkey"
      columns: ["transfer_id"]
isOneToOne: false
      referencedRelation: "transfers"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "transfer_lines_transfer_id_fkey"
      columns: ["transfer_id"]
isOneToOne: false
      referencedRelation: "v_transfer_in_transit"
      referencedColumns: ["transfer_id"]
    }
                  ]
                },"transfers": {
                  Row: {
                    "created_at": string,"created_by": string,"dispatched_by": string | null,"from_warehouse_id": string,"id": string,"org_id": string,"received_by": string | null,"resolved_by": string | null,"shortage_reason": string | null,"status": string,"to_warehouse_id": string,"updated_at": string
                  }
                  ComputedFields: never
                  Insert: {
                    "created_at"?: string,"created_by": string,"dispatched_by"?: string | null,"from_warehouse_id": string,"id"?: string,"org_id": string,"received_by"?: string | null,"resolved_by"?: string | null,"shortage_reason"?: string | null,"status"?: string,"to_warehouse_id": string,"updated_at"?: string
                  }
                  Update: {
                    "created_at"?: string,"created_by"?: string,"dispatched_by"?: string | null,"from_warehouse_id"?: string,"id"?: string,"org_id"?: string,"received_by"?: string | null,"resolved_by"?: string | null,"shortage_reason"?: string | null,"status"?: string,"to_warehouse_id"?: string,"updated_at"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "transfers_created_by_fkey"
      columns: ["created_by"]
isOneToOne: false
      referencedRelation: "profiles"
      referencedColumns: ["user_id"]
    },{
      foreignKeyName: "transfers_dispatched_by_fkey"
      columns: ["dispatched_by"]
isOneToOne: false
      referencedRelation: "profiles"
      referencedColumns: ["user_id"]
    },{
      foreignKeyName: "transfers_from_warehouse_id_fkey"
      columns: ["from_warehouse_id"]
isOneToOne: false
      referencedRelation: "v_warehouses"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "transfers_from_warehouse_id_fkey"
      columns: ["from_warehouse_id"]
isOneToOne: false
      referencedRelation: "warehouses"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "transfers_org_id_fkey"
      columns: ["org_id"]
isOneToOne: false
      referencedRelation: "organisations"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "transfers_org_id_fkey"
      columns: ["org_id"]
isOneToOne: false
      referencedRelation: "v_organisations"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "transfers_received_by_fkey"
      columns: ["received_by"]
isOneToOne: false
      referencedRelation: "profiles"
      referencedColumns: ["user_id"]
    },{
      foreignKeyName: "transfers_resolved_by_fkey"
      columns: ["resolved_by"]
isOneToOne: false
      referencedRelation: "profiles"
      referencedColumns: ["user_id"]
    },{
      foreignKeyName: "transfers_to_warehouse_id_fkey"
      columns: ["to_warehouse_id"]
isOneToOne: false
      referencedRelation: "v_warehouses"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "transfers_to_warehouse_id_fkey"
      columns: ["to_warehouse_id"]
isOneToOne: false
      referencedRelation: "warehouses"
      referencedColumns: ["id"]
    }
                  ]
                },"variance_cases": {
                  Row: {
                    "carrier_user_id": string,"created_at": string,"id": string,"kind": string,"org_id": string,"qty_pieces": number,"raised_journal_id": string | null,"resolution_note": string | null,"resolved_at": string | null,"resolved_by": string | null,"resolved_journal_id": string | null,"shipment_id": string,"sku_id": string,"status": string,"value_kobo": number
                  }
                  ComputedFields: never
                  Insert: {
                    "carrier_user_id": string,"created_at"?: string,"id"?: string,"kind"?: string,"org_id": string,"qty_pieces": number,"raised_journal_id"?: string | null,"resolution_note"?: string | null,"resolved_at"?: string | null,"resolved_by"?: string | null,"resolved_journal_id"?: string | null,"shipment_id": string,"sku_id": string,"status"?: string,"value_kobo": number
                  }
                  Update: {
                    "carrier_user_id"?: string,"created_at"?: string,"id"?: string,"kind"?: string,"org_id"?: string,"qty_pieces"?: number,"raised_journal_id"?: string | null,"resolution_note"?: string | null,"resolved_at"?: string | null,"resolved_by"?: string | null,"resolved_journal_id"?: string | null,"shipment_id"?: string,"sku_id"?: string,"status"?: string,"value_kobo"?: number
                  }
                  Relationships: [
                    {
      foreignKeyName: "variance_cases_carrier_user_id_fkey"
      columns: ["carrier_user_id"]
isOneToOne: false
      referencedRelation: "profiles"
      referencedColumns: ["user_id"]
    },{
      foreignKeyName: "variance_cases_org_id_fkey"
      columns: ["org_id"]
isOneToOne: false
      referencedRelation: "organisations"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "variance_cases_org_id_fkey"
      columns: ["org_id"]
isOneToOne: false
      referencedRelation: "v_organisations"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "variance_cases_raised_journal_id_fkey"
      columns: ["raised_journal_id"]
isOneToOne: false
      referencedRelation: "journals"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "variance_cases_resolved_by_fkey"
      columns: ["resolved_by"]
isOneToOne: false
      referencedRelation: "profiles"
      referencedColumns: ["user_id"]
    },{
      foreignKeyName: "variance_cases_resolved_journal_id_fkey"
      columns: ["resolved_journal_id"]
isOneToOne: false
      referencedRelation: "journals"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "variance_cases_shipment_id_fkey"
      columns: ["shipment_id"]
isOneToOne: false
      referencedRelation: "shipments"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "variance_cases_shipment_id_fkey"
      columns: ["shipment_id"]
isOneToOne: false
      referencedRelation: "v_shipment_reconciliation"
      referencedColumns: ["shipment_id"]
    },{
      foreignKeyName: "variance_cases_sku_id_fkey"
      columns: ["sku_id"]
isOneToOne: false
      referencedRelation: "skus"
      referencedColumns: ["id"]
    }
                  ]
                },"warehouses": {
                  Row: {
                    "active": boolean,"branch_id": string,"created_at": string,"id": string,"location": unknown,"name": string,"org_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "active"?: boolean,"branch_id": string,"created_at"?: string,"id"?: string,"location": unknown,"name": string,"org_id": string
                  }
                  Update: {
                    "active"?: boolean,"branch_id"?: string,"created_at"?: string,"id"?: string,"location"?: unknown,"name"?: string,"org_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "warehouses_branch_id_org_id_fkey"
      columns: ["branch_id","org_id"]
isOneToOne: false
      referencedRelation: "branches"
      referencedColumns: ["id","org_id"]
    }
                  ]
                }
          }
          Views: {
            "v_account_balances": {
                  Row: {
                    "account_id": string | null,"account_type": Database["public"]['Enums']["account_type"] | null,"balance_kobo": number | null,"book_org_id": string | null,"normal_side": string | null,"updated_at": string | null
                  }
                  ComputedFields: never
                  Insert: {
                           "account_id"?: string | null,"account_type"?: Database["public"]['Enums']["account_type"] | null,"balance_kobo"?: never,"book_org_id"?: string | null,"normal_side"?: never,"updated_at"?: string | null
                         }
                        Update: {
                           "account_id"?: string | null,"account_type"?: Database["public"]['Enums']["account_type"] | null,"balance_kobo"?: never,"book_org_id"?: string | null,"normal_side"?: never,"updated_at"?: string | null
                         }
                        Relationships: [
                    {
      foreignKeyName: "account_balances_account_id_fkey"
      columns: ["account_id"]
isOneToOne: true
      referencedRelation: "accounts"
      referencedColumns: ["id"]
    }
                  ]
                },"v_current_prices": {
                  Row: {
                    "distributor_org_id": string | null,"effective_from": string | null,"price_kobo": number | null,"price_list_id": string | null,"sku_id": string | null,"uom_code": string | null
                  }
                  ComputedFields: never
                  Relationships: [
                    {
      foreignKeyName: "price_list_items_sku_id_uom_code_fkey"
      columns: ["sku_id","uom_code"]
isOneToOne: false
      referencedRelation: "sku_uom"
      referencedColumns: ["sku_id","uom_code"]
    }
                  ]
                },"v_orders": {
                  Row: {
                    "cancelled_reason": string | null,"confirmed_at": string | null,"created_at": string | null,"distributor_org_id": string | null,"id": string | null,"placed_by_role": Database["public"]['Enums']["member_role"] | null,"retailer_org_id": string | null,"routing_decision": Json | null,"routing_reason": string | null,"status": Database["public"]['Enums']["order_status"] | null,"total_kobo": number | null
                  }
                  ComputedFields: never
                  Insert: {
                           "cancelled_reason"?: string | null,"confirmed_at"?: string | null,"created_at"?: string | null,"distributor_org_id"?: string | null,"id"?: string | null,"placed_by_role"?: Database["public"]['Enums']["member_role"] | null,"retailer_org_id"?: string | null,"routing_decision"?: Json | null,"routing_reason"?: string | null,"status"?: Database["public"]['Enums']["order_status"] | null,"total_kobo"?: never
                         }
                        Update: {
                           "cancelled_reason"?: string | null,"confirmed_at"?: string | null,"created_at"?: string | null,"distributor_org_id"?: string | null,"id"?: string | null,"placed_by_role"?: Database["public"]['Enums']["member_role"] | null,"retailer_org_id"?: string | null,"routing_decision"?: Json | null,"routing_reason"?: string | null,"status"?: Database["public"]['Enums']["order_status"] | null,"total_kobo"?: never
                         }
                        Relationships: [
                    {
      foreignKeyName: "orders_distributor_org_id_retailer_org_id_fkey"
      columns: ["distributor_org_id","retailer_org_id"]
isOneToOne: false
      referencedRelation: "customer_relationships"
      referencedColumns: ["distributor_org_id","retailer_org_id"]
    }
                  ]
                },"v_organisations": {
                  Row: {
                    "geofence_max_accuracy_m": number | null,"geofence_radius_m": number | null,"id": string | null,"kind": Database["public"]['Enums']["org_kind"] | null,"lat": number | null,"lng": number | null,"location_accuracy_m": number | null,"name": string | null,"slug": string | null,"split_threshold_m": number | null,"status": Database["public"]['Enums']["record_status"] | null
                  }
                  ComputedFields: never
                  Insert: {
                           "geofence_max_accuracy_m"?: number | null,"geofence_radius_m"?: number | null,"id"?: string | null,"kind"?: Database["public"]['Enums']["org_kind"] | null,"lat"?: never,"lng"?: never,"location_accuracy_m"?: number | null,"name"?: string | null,"slug"?: string | null,"split_threshold_m"?: number | null,"status"?: Database["public"]['Enums']["record_status"] | null
                         }
                        Update: {
                           "geofence_max_accuracy_m"?: number | null,"geofence_radius_m"?: number | null,"id"?: string | null,"kind"?: Database["public"]['Enums']["org_kind"] | null,"lat"?: never,"lng"?: never,"location_accuracy_m"?: number | null,"name"?: string | null,"slug"?: string | null,"split_threshold_m"?: number | null,"status"?: Database["public"]['Enums']["record_status"] | null
                         }
                        Relationships: [
                    
                  ]
                },"v_shipment_reconciliation": {
                  Row: {
                    "damaged": number | null,"org_id": string | null,"picked_up": number | null,"remaining": number | null,"returned": number | null,"shipment_id": string | null,"sku_id": string | null,"sold": number | null,"status": string | null
                  }
                  ComputedFields: never
                  Relationships: [
                    {
      foreignKeyName: "shipments_org_id_fkey"
      columns: ["org_id"]
isOneToOne: false
      referencedRelation: "organisations"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "shipments_org_id_fkey"
      columns: ["org_id"]
isOneToOne: false
      referencedRelation: "v_organisations"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "stock_movements_sku_id_fkey"
      columns: ["sku_id"]
isOneToOne: false
      referencedRelation: "skus"
      referencedColumns: ["id"]
    }
                  ]
                },"v_territories": {
                  Row: {
                    "branch_id": string | null,"has_boundary": boolean | null,"id": string | null,"name": string | null,"org_id": string | null
                  }
                  ComputedFields: never
                  Insert: {
                           "branch_id"?: string | null,"has_boundary"?: never,"id"?: string | null,"name"?: string | null,"org_id"?: string | null
                         }
                        Update: {
                           "branch_id"?: string | null,"has_boundary"?: never,"id"?: string | null,"name"?: string | null,"org_id"?: string | null
                         }
                        Relationships: [
                    {
      foreignKeyName: "territories_branch_id_org_id_fkey"
      columns: ["branch_id","org_id"]
isOneToOne: false
      referencedRelation: "branches"
      referencedColumns: ["id","org_id"]
    }
                  ]
                },"v_transfer_in_transit": {
                  Row: {
                    "in_transit": number | null,"org_id": string | null,"sku_id": string | null,"transfer_id": string | null
                  }
                  ComputedFields: never
                  Relationships: [
                    {
      foreignKeyName: "stock_movements_sku_id_fkey"
      columns: ["sku_id"]
isOneToOne: false
      referencedRelation: "skus"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "transfers_org_id_fkey"
      columns: ["org_id"]
isOneToOne: false
      referencedRelation: "organisations"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "transfers_org_id_fkey"
      columns: ["org_id"]
isOneToOne: false
      referencedRelation: "v_organisations"
      referencedColumns: ["id"]
    }
                  ]
                },"v_warehouses": {
                  Row: {
                    "active": boolean | null,"branch_id": string | null,"id": string | null,"lat": number | null,"lng": number | null,"name": string | null,"org_id": string | null
                  }
                  ComputedFields: never
                  Insert: {
                           "active"?: boolean | null,"branch_id"?: string | null,"id"?: string | null,"lat"?: never,"lng"?: never,"name"?: string | null,"org_id"?: string | null
                         }
                        Update: {
                           "active"?: boolean | null,"branch_id"?: string | null,"id"?: string | null,"lat"?: never,"lng"?: never,"name"?: string | null,"org_id"?: string | null
                         }
                        Relationships: [
                    {
      foreignKeyName: "warehouses_branch_id_org_id_fkey"
      columns: ["branch_id","org_id"]
isOneToOne: false
      referencedRelation: "branches"
      referencedColumns: ["id","org_id"]
    }
                  ]
                }
          }
          Functions: {
            [_ in never]: never
          }
          Enums: {
            "account_type": "provider_clearing"|"wallet"|"partner_funds"|"receivables"|"trade_credit"|"cash_in_transit"|"variance"|"variance_offset"|"sales_revenue","location_kind": "warehouse"|"agent"|"driver","member_role": "platform_admin"|"manufacturer_admin"|"distributor_admin"|"branch_manager"|"warehouse_staff"|"driver"|"agent"|"retailer","movement_type": "receipt"|"reserve"|"release"|"transfer_out"|"transfer_in"|"handover"|"sale"|"return"|"damage"|"adjustment","order_kind": "pull"|"primary","order_status": "placed"|"awaiting_split_decision"|"reserved"|"rejected"|"batched"|"packed"|"dispatched"|"delivered"|"partially_delivered"|"failed_delivery"|"settled"|"cancelled","org_kind": "platform"|"manufacturer"|"distributor"|"retailer","record_status": "pending"|"active"|"suspended"|"rejected"
          }
          CompositeTypes: {
            [_ in never]: never
          }
        }
}

type DatabaseWithoutInternals = Omit<Database, '__InternalSupabase'>

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never
> = DefaultSchemaTableNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
  ? (DefaultSchema["Tables"] & DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
      Row: infer R
    }
    ? R
    : never
  : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never
> = DefaultSchemaTableNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
  ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
      Insert: infer I
    }
    ? I
    : never
  : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never
> = DefaultSchemaTableNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
  ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
      Update: infer U
    }
    ? U
    : never
  : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never
> = DefaultSchemaEnumNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
  ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
  : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never
> = PublicCompositeTypeNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
  ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
  : never

export const Constants = {
  "app": {
          Enums: {
            
          }
        },"public": {
          Enums: {
            "account_type": ["provider_clearing", "wallet", "partner_funds", "receivables", "trade_credit", "cash_in_transit", "variance", "variance_offset", "sales_revenue"],"location_kind": ["warehouse", "agent", "driver"],"member_role": ["platform_admin", "manufacturer_admin", "distributor_admin", "branch_manager", "warehouse_staff", "driver", "agent", "retailer"],"movement_type": ["receipt", "reserve", "release", "transfer_out", "transfer_in", "handover", "sale", "return", "damage", "adjustment"],"order_kind": ["pull", "primary"],"order_status": ["placed", "awaiting_split_decision", "reserved", "rejected", "batched", "packed", "dispatched", "delivered", "partially_delivered", "failed_delivery", "settled", "cancelled"],"org_kind": ["platform", "manufacturer", "distributor", "retailer"],"record_status": ["pending", "active", "suspended", "rejected"]
          }
        }
} as const
