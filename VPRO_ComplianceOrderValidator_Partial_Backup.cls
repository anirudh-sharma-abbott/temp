/**
 * @description an Apex  class Compliance Order Validation Utility.
 *
 **********************************************************************
 *
 *               Confidentiality Information:
 *
 * This module is based on pre-existing content developed and owned
 * by Veeva Systems Inc.; this may only be used in connection with the
 * deliverable with which it was provided to Customer.
 *
 * Copyright (c) 2019 Veeva Systems, Inc.  All Rights Reserved.
 *
 * Last Modified: 12/07/2020
 * Disabled the VT Sampling message, that was in place for HCP-CGM orders
 * Last Modified: 04/30/2021
 * Fixed a bug in the logic for creation of POC-CGM orders. HCP's
 * Specialty value of HOSPITALIST overrides the Approved Specialty Flag.
 * Last Modified: 07/28/2021
 * Update Welcome Letter code from ADC-25511v1.0-EA to ADC-25511v2.0-EA
 * Last Modified: 01/06/2022
 * While counting the Annual Quantity, exclude returned quantity
 **********************************************************************/
public class VPRO_ComplianceOrderValidator {
	static Map<Id, Schema.RecordTypeInfo> rtMapById = null;
	static Map<String, Schema.RecordTypeInfo> rtMapByName = null;
	private static Map<String, Map<String, Compliance_Order_Setting__mdt>> mCompOrderSetting = new Map<String, Map<String, Compliance_Order_Setting__mdt>>();
	private static Map<String, Compliance_Existing_Order_Rules__mdt> mExistingOrderRules = new Map<String, Compliance_Existing_Order_Rules__mdt>();
	private static Set<String> lOrderTypeWithAnnualLimit = new Set<String>();
	public static final String DATA_CABLE_REQUEST_ORDER_TYPE = 'Data Cable Request';
	public static final String EVALUATION_ORDER_TYPE = 'Evaluation';
	public static final String MANAGEMENT_ORDER_TYPE = 'Management Order';
	public static final String MANAGEMENT_ORDER_CGM_ORDER_TYPE = 'Management Orders-CGM';
	public static final String SENSING_EDUCATION_ITEMS_ORDER_TYPE = 'Sensing Educational Items';
	public static final String CONTRACTED_CUSTOMER_ORDER_TYPE = 'Contracted Customers Module';
	public static final String BRAND_DEVELOPMENT_ORDER_TYPE = 'Brand Development';
	public static final String CHARITABLE_DONATIONS_ORDER_TYPE = 'Charitable Donations';
	public static final String EVALUATION_CGM_ORDER_TYPE = 'Evaluation-CGM';
	public static final String NCO_WEB_SAMPLING = 'NCO Web Sampling';
	//KK - HCP_Experience
	public static final String HCP_EXPERIENCE_ORDER_TYPE = 'HCP Experience';
	public static final String HCP_FIRSTHAND_EXPERIENCE_ORDER_TYPE = 'HCP Firsthand Experience';

	public static final String TAndCProductCode = 'VF0019';
	// public static final String WelcomeLetterProductCode='ADC-16458v1.0-EA';
	// Products listed in this set are not showin for user selection
	public static final Set<String> WelcomeLetterProductCode = new Set<String>{
		'VF0006',
		'VF0021',
		'ADC-25511v2.0-EA'
	};
	private static Boolean isComplianceTeamMember = null;

	// Add the quantities from the orders of following Product Group(s) previously placed this year
	// to check against the limit of Yearly Total Demo Kits
	public static final String CURRENT_DEMOKIT_PRODUCT_DESC = 'Demo Kit 2 Day';
	public static final Set<String> PREV_DEMOKIT_PRODUCT_DESC = new Set<String>{ 'Demo Kit 14 Day', 'Demo Kit 2 Day' };

	// SC. 08/17/2020 release. Add 14 Day Sensor
	// Enabling 14Day Sensor Kit in additon to FSL2 products for a short duration
	// This product will go away once we run out of samples
	// Set of Products identified by their External IDs listed here would be considered
	// additional group since it is in addition to the primary group of products

	// As per the requirement, if user adds FSL2 (primary) group of products to the order,
	// the products listed in this Set are NOT allowed to be added to the order.
	// User should create a separate order with these products.
	// This code will work fine even when 14Day Sensor is disabled in Product Catalog
	public static final Set<String> ADDTL_GROUP_OF_PRODUCTS = new Set<String>{ '71939-01' };

	// Or, you can comment out the above line and open up the below line when 14Day Sensor is disabled.
	//public static final Set<String> ADDTL_GROUP_OF_PRODUCTS = new Set<String>();

	// SC. 08/12/2020
	// If the HCP of a POC channel has the following Specialty, then this overrides the FSL2 Approved Specialty flag
	// and HCP can order FSL2 products irrespective of the value of FSL2 Approved Specialty flag.
	public static final Set<String> POC_HCP_SPECIALTY_OVERRIDE = new Set<String>{
		'HOSPITALIST',
		'HOSPITALIST (PEDIATRICS)'
	};

	static {
		Schema.DescribeSObjectResult d = Schema.SObjectType.ADC_Compliance_Order__c;
		rtMapById = d.getRecordTypeInfosById();
		rtMapByName = d.getRecordTypeInfosByDeveloperName();

		List<Compliance_Order_Setting__mdt> lCompOrderSettings = [
			SELECT
				Label,
				Product_Code__c,
				Channel__c,
				Product_Type__c,
				Send_to_pending__c,
				Submit_Record_Type_API__c,
				OverrideAccountLevel__c,
				Per_Order_Limit_Account_Field_API_Name__c,
				Final_Status__c,
				Per_Year_Limit_Account_Field_Name__c,
				Num_of_Months_Since_Last_Order__c,
				By_Pass_Validation_By_Compliance_Team__c,
				OrderType__c,
				Per_Order_Limit__c,
				Per_Year_Limit__c,
				Non_Physical__c,
				has_GSG__c
			FROM Compliance_Order_Setting__mdt
		];

		for (Compliance_Order_Setting__mdt coSetting : lCompOrderSettings) {
			Map<String, Compliance_Order_Setting__mdt> mtmp = new Map<String, Compliance_Order_Setting__mdt>();
			if (mCompOrderSetting.containsKey(coSetting.OrderType__c)) {
				mtmp = mCompOrderSetting.get(coSetting.OrderType__c);
			}

			String key =
				coSetting.OrderType__c +
				((coSetting.Channel__c != null) ? ':' + coSetting.Channel__c : ':ALL') +
				((coSetting.Product_Type__c != null) ? ':' + coSetting.Product_Type__c : ':ALL') +
				((coSetting.Product_Code__c != null) ? ':' + coSetting.Product_Code__c : '');

			// AZ - 3-7-24
			// if(coSetting.Product_Type__c != null){
			//     key += ':' + coSetting.Product_Type__c;
			// }else if(coSetting.Product_Type__c == null && coSetting.Product_Code__c == null){
			//     key += ':ALL';
			// }else if(coSetting.Product_Type__c == null && coSetting.Product_Code__c != null){
			//     key += ':';
			// }

			//key += ((coSetting.Product_Code__c != null)?':'+coSetting.Product_Code__c:'');

			mtmp.put(key, coSetting);
			mCompOrderSetting.put(coSetting.OrderType__c, mtmp);

			if (coSetting.Per_Year_Limit__c != null || coSetting.Num_of_Months_Since_Last_Order__c != null) {
				lOrderTypeWithAnnualLimit.add(coSetting.OrderType__c);
			}
		}

		List<Compliance_Existing_Order_Rules__mdt> lExistingOrderRules = [
			SELECT Order_Type__c, Channel__c, HCO__c, HCP__c, Address__c, Status__c, Bypass_Rule_for_Compliance_Team__c
			FROM Compliance_Existing_Order_Rules__mdt
		];
		for (Compliance_Existing_Order_Rules__mdt rule : lExistingOrderRules) {
			String key = rule.Order_Type__c + ':' + rule.Channel__c;
			mExistingOrderRules.put(key, rule);
		}
	}

	public static boolean validate(List<ADC_Compliance_Order__c> newItems, Map<Id, ADC_Compliance_Order__c> oldItems) {
		System.debug('**** validate');
		Map<String, List<ADC_Compliance_Order__c>> mOrderTypeToOrderList = new Map<String, List<ADC_Compliance_Order__c>>();
		Map<String, List<ADC_Order_Product__c>> mOrderToOrderProduct = new Map<String, List<ADC_Order_Product__c>>();

		Set<Id> orderIdSet = new Set<Id>();
		List<ADC_Compliance_Order__c> orderIdSetToVerifySampleLimit = new List<ADC_Compliance_Order__c>();
		List<ADC_Compliance_Order__c> orderIdSetToVerifyContract = new List<ADC_Compliance_Order__c>();
		//KK - HCP_Experience
		List<ADC_Compliance_Order__c> orderIdSetToVerifyHCPWear = new List<ADC_Compliance_Order__c>();
		Set<Id> hcpIds = new Set<Id>();
		Set<Id> contractAccIds = new Set<Id>();
		// Map<String,  Map<Id, Map<String, Decimal>>> mOrderTypeToAccCount = new  Map<String,  Map<id, Map<String, Decimal>>>();
		//Create Map<OrderType,Map<AccountId,Map<Channel,Map<ProductGroup,Count>
		Map<String, Map<Id, Map<String, Map<String, Decimal>>>> mOrderTypeToAccCount = new Map<String, Map<id, Map<String, Map<String, Decimal>>>>();
		List<ADC_Compliance_Order__c> submittedOrders = new List<ADC_Compliance_Order__c>();
		for (ADC_Compliance_Order__c newRecord : newItems) {
			ADC_Compliance_Order__c oldRecord = (oldItems != null) ? oldItems.get(newRecord.id) : null;

			if (
				(newRecord.ADC_Status__c == 'Draft') &&
				(newRecord.ADC_Channel__c == 'HCP' ||
				newRecord.ADC_Channel__c == 'Market Access') &&
				newRecord.ADC_Order_Type__c == MANAGEMENT_ORDER_CGM_ORDER_TYPE
			) {
				System.debug('** HCP-Management-CGM Order of Draft status...');
				orderIdSetToVerifySampleLimit.add(newRecord);
				hcpIds.add(newRecord.ADC_Contact_Name__c);
			}
			if ((newRecord.ADC_Status__c == 'Draft') && newRecord.ADC_Order_Type__c == CONTRACTED_CUSTOMER_ORDER_TYPE) {
				System.debug('** Contracted Customer of Draft status...');
				orderIdSetToVerifyContract.add(newRecord);
				contractAccIds.add(newRecord.ADC_Account_Name__c);
			}
			//KK - HCP_Experience
			if ((newRecord.ADC_Status__c == 'Draft') && newRecord.ADC_Order_Type__c == HCP_EXPERIENCE_ORDER_TYPE) {
				System.debug('** HCP Experience of Draft status with valid email domain...');
				orderIdSetToVerifyHCPWear.add(newRecord);
			}
			if (
				newRecord.ADC_Status__c == 'Submitted' &&
				(oldRecord == null || (oldRecord != null && oldRecord.ADC_Status__c != 'Submitted'))
			) {
				validateAddress(newRecord);
				//AZ - Set Status to Pending for Email Domains that are not @ihs.gov, @va.gov, or @mil.com
				validateEmail(newRecord);
				submittedOrders.add(newRecord);
			}
		}

		List<ADC_Compliance_Order__c> validOrders = VPRO_ComplianceOrderValidator.validateInProgressOrderExists(
			submittedOrders
		);

		System.debug('** validOrders KK...' + validOrders);

		if (validOrders != null && !validOrders.isEmpty()) {
			for (ADC_Compliance_Order__c newRecord : validOrders) {
				List<ADC_Compliance_Order__c> tmpList = new List<ADC_Compliance_Order__c>();
				if (mOrderTypeToOrderList.containsKey(newRecord.ADC_Order_Type__c)) {
					tmpList = mOrderTypeToOrderList.get(newRecord.ADC_Order_Type__c);
				}
				tmpList.add(newRecord);
				mOrderTypeToOrderList.put(newRecord.ADC_Order_Type__c, tmpList);
				if (newRecord.Id != null) {
					orderIdSet.add(newRecord.Id);
					System.debug('** orderIdSet...' + orderIdSet);
				}
			}
		}
		// AZ 4-3-24  - Query for T&C Product Codes to exclude from Compliance_Order_Settings__c
		List<Compliance_Order_Settings__c> complianceOrderSettings = [
			SELECT TAndCProductCodes__c
			FROM Compliance_Order_Settings__c
		];
		List<String> TAndCProductCodes = complianceOrderSettings[0].TAndCProductCodes__c.split(',');

		if (!orderIdSet.isEmpty()) {
			List<ADC_Order_Product__c> lOrderProduct = [
				SELECT
					Id,
					Name,
					ADC_Description__c,
					ADC_Product__r.name,
					ADC_Product__r.External_ID_vod__c,
					ADC_Product__r.Product_Type_vod__c,
					ADC_Product__r.Sensor_External_Id__c,
					ADC_Product__c,
					ADC_Order__c,
					ADC_Product__r.ADC_Product_Group_Desc__c,
					ADC_Order_Type__c,
					ADC_Product_Code__c,
					ADC_Order__r.ADC_Contact_Name__c,
					ADC_Order__r.ADC_Account_Name__c,
					ADC_Order__r.ADC_Channel__c,
					ADC_Order__r.ADC_Account_Name__r.ADC_Sample_Quantity_Limit_Per_Order__c,
					ADC_Quantity__c
				FROM ADC_Order_Product__c
				WHERE
					ADC_Order__c IN :orderIdSet
					AND ADC_Product__r.External_ID_vod__c != :VPRO_ComplianceOrderValidator.TAndCProductCode
			];
			for (ADC_Order_Product__c op : lOrderProduct) {
				System.debug('**sc1: ' + op);
				List<ADC_Order_Product__c> lTmp = new List<ADC_Order_Product__c>();
				// AZ 4-3-24 - If the current Order Product is a T&C Product, then skip over
				if (!TAndCProductCodes.contains(op.ADC_Product__r.External_ID_vod__c)) {
					if (mOrderToOrderProduct.containsKey(op.ADC_Order__c)) {
						lTmp = mOrderToOrderProduct.get(op.ADC_Order__c);
					}
					lTmp.add(op);
					mOrderToOrderProduct.put(op.ADC_Order__c, lTmp);
					mOrderTypeToAccCount = createAccountCountMap(op, mOrderTypeToAccCount);
				}
			}
		}

		if (!orderIdSetToVerifySampleLimit.isEmpty()) {
			System.debug('** verifySampleLimitHasBeenSet');
			verifySampleLimitHasBeenSet(orderIdSetToVerifySampleLimit, getHCPSampleLimits(hcpIds));

			// Disable the VT Sampling Message, that was in place for HCP-CGM Orders
			// SC. 12/07/2020
			//System.debug('** validateVAAddress');
			//validateVAAddress(orderIdSetToVerifySampleLimit,hcpIds);
		} else {
			System.debug('*** orderIdSetToVerifySampleLimit: ' + orderIdSetToVerifySampleLimit);
			System.debug('** Not an HCP-Management-CGM order. So HCP Sample Limits not checked.');
		}

		if (!orderIdSetToVerifyContract.isEmpty()) {
			System.debug('** verifyContract Has been set');
			verifyContractExists(orderIdSetToVerifyContract, getContract(contractAccIds));
		} else {
			System.debug('*** orderIdSetToVerifyContract: ' + orderIdSetToVerifySampleLimit);
			System.debug('** Not an Contracted customer Order type. So Contract is  not checked.');
		}
		System.debug('mOrderTypeToAccCount->' + mOrderTypeToAccCount);

		if (!mOrderTypeToOrderList.isEmpty()) {
			for (String key : mOrderTypeToOrderList.keySet()) {
				List<ADC_Compliance_Order__c> lOrderList = (List<ADC_Compliance_Order__c>) mOrderTypeToOrderList.get(
					key
				);

				switch on key {
					when 'Data Cable Request' {
						validateDataCableRequest(lOrderList, mOrderToOrderProduct, mOrderTypeToAccCount);
					}
					when 'Evaluation' {
						validateEvaluationRequest(lOrderList, mOrderToOrderProduct, mOrderTypeToAccCount);
					}
					when 'Management Order' {
						validateManagementOrderRequest(lOrderList, mOrderToOrderProduct, mOrderTypeToAccCount);
					}
					when 'Management Orders-CGM' {
						validateManagementOrderCGMRequest(lOrderList, mOrderToOrderProduct, mOrderTypeToAccCount);
					}
					when 'Sensing Educational Items' {
						validateSensignEduItemsRequest(lOrderList, mOrderToOrderProduct, mOrderTypeToAccCount);
					}
					when 'Contracted Customers Module' {
						validateContractedCustomerRequest(lOrderList, mOrderToOrderProduct, mOrderTypeToAccCount);
					}
					when 'HCP Experience' {
						//KK - HCP_Experience
						validateHCPExperienceRequest(lOrderList, mOrderToOrderProduct, mOrderTypeToAccCount);
					}
					when 'HCP Firsthand Experience' {
						//KK - HCP_Experience
						validateHCPFirstExperienceRequest(lOrderList, mOrderToOrderProduct, mOrderTypeToAccCount);
					}
					when 'NCO Web Sampling' {
						validateNCOWebSamplingOrders(lOrderList, mOrderToOrderProduct);
					}
					when else {
						validateGenericOrders(lOrderList, mOrderToOrderProduct);
					}
				}
			}
		}

		return true;
	}

	//KK - HCP_Experience
	private static void validateHCPExperienceRequest(
		List<ADC_Compliance_Order__c> lOrderList,
		Map<String, List<ADC_Order_Product__c>> mOrderToOrderProduct,
		Map<String, Map<Id, Map<String, Map<String, Decimal>>>> mOrderTypeToAccCount
	) {
		System.debug('mCompOrderSetting::' + mCompOrderSetting);
		Map<String, Compliance_Order_Setting__mdt> mOrdSettings = mCompOrderSetting.get('HCP Experience');
		System.debug('mOrdSettings::' + mOrdSettings);

		//AZ - 3-6-24
		Set<Id> acctIds = new Set<Id>();
		for (ADC_Compliance_Order__c o : lOrderList) {
			acctIds.add(o.ADC_Contact_Name__c);
		}
		// Map of Acct Id to Account which already have HCP Wear CO
		Map<String, Account> mAccToContract = getHCPWearContract(acctIds);

		//AZ - 3-1-24 Update
		Map<ADC_Compliance_Order__c, StatusWrapper> invalidOrders = new Map<ADC_Compliance_Order__c, StatusWrapper>();
		List<ADC_HCP_Wear_Contracts__c> lContracts = [
			SELECT Id, ADC_Product_Catalog__c, ADC_LotOrSerial_Number__c
			FROM ADC_HCP_Wear_Contracts__c
			WHERE ADC_Begin_Date__c <= TODAY AND ADC_End_Date__c >= TODAY AND ADC_Remaining_Quantity__c > 0
			and adc_order_type__c ='HCP Experience'
		];
		invalidOrders.putAll(checkForHCPWearProduts(lOrderList, mOrderToOrderProduct, lContracts));

		for (ADC_Compliance_Order__c o : lOrderList) {
			if (!invalidOrders.containsKey(o) && !mAccToContract.containsKey(o.ADC_Contact_Name__c)) {
				List<ADC_Order_Product__c> productsList = mOrderToOrderProduct.get(o.Id);
				if (productsList != null) {
					for (ADC_Order_Product__c product : productsList) {
						String key =
							o.ADC_Order_Type__c +
							((o.ADC_Channel__c != null) ? ':' + o.ADC_Channel__c : ':ALL') +
							((product.ADC_Product__r.ADC_Product_Group_Desc__c != null)
								? ':' + product.ADC_Product__r.ADC_Product_Group_Desc__c
								: ':ALL') +
							((product.ADC_Description__c != null) ? ':' + product.ADC_Description__c : '');

						Compliance_Order_Setting__mdt ordSettings = (Compliance_Order_Setting__mdt) mOrdSettings.get(
							key
						);
						System.debug('ordSettings::' + ordSettings);
						if (ordSettings != null) {
							Schema.RecordTypeInfo toUpdateRecInfo = rtMapByName.get('HCP_Experience_Submitted');
							String submitRecordTypeId = toUpdateRecInfo.recordtypeid;
							o.RecordTypeId = submitRecordTypeId;
							if (o.ADC_Status__c != 'Pending') {
								o.ADC_Status__c = ordSettings.Final_Status__c;
							}
						}
					}
				}
			} else if (mAccToContract.containsKey(o.ADC_Contact_Name__c)) {
				o.addError('There is an existing HCP Wear Experience Order for this HCP');
			}
		}
	}

	private static void validateHCPFirstExperienceRequest(
		List<ADC_Compliance_Order__c> lOrderList,
		Map<String, List<ADC_Order_Product__c>> mOrderToOrderProduct,
		Map<String, Map<Id, Map<String, Map<String, Decimal>>>> mOrderTypeToAccCount
	) {
		System.debug('mCompOrderSetting::' + mCompOrderSetting);
		Map<String, Compliance_Order_Setting__mdt> mOrdSettings = mCompOrderSetting.get('HCP Firsthand Experience');
		System.debug('mOrdSettings::' + mOrdSettings);

		//AZ - 3-6-24
		Set<Id> acctIds = new Set<Id>();
		for (ADC_Compliance_Order__c o : lOrderList) {
			acctIds.add(o.ADC_Contact_Name__c);
		}
		// Map of Acct Id to Account which already have HCP Wear CO
		Map<String, Account> mAccToContract = getHCPWearContract(acctIds);

		//AZ - 3-1-24 Update
		Map<ADC_Compliance_Order__c, StatusWrapper> invalidOrders = new Map<ADC_Compliance_Order__c, StatusWrapper>();
		List<ADC_HCP_Wear_Contracts__c> lContracts = [
			SELECT Id, ADC_Product_Catalog__c, ADC_LotOrSerial_Number__c
			FROM ADC_HCP_Wear_Contracts__c
			WHERE ADC_Begin_Date__c <= TODAY AND ADC_End_Date__c >= TODAY AND ADC_Remaining_Quantity__c > 0
			and adc_order_type__c ='HCP Firsthand Experience'
		];
		invalidOrders.putAll(checkForHCPWearProduts(lOrderList, mOrderToOrderProduct, lContracts));

		for (ADC_Compliance_Order__c o : lOrderList) {
			if (!invalidOrders.containsKey(o) && !mAccToContract.containsKey(o.ADC_Contact_Name__c)) {
				List<ADC_Order_Product__c> productsList = mOrderToOrderProduct.get(o.Id);
				if (productsList != null) {
					for (ADC_Order_Product__c product : productsList) {
						String key =
							o.ADC_Order_Type__c +
							((o.ADC_Channel__c != null) ? ':' + o.ADC_Channel__c : ':ALL') +
							((product.ADC_Product__r.ADC_Product_Group_Desc__c != null)
								? ':' + product.ADC_Product__r.ADC_Product_Group_Desc__c
								: ':ALL') +
							((product.ADC_Description__c != null) ? ':' + product.ADC_Description__c : '');

						Compliance_Order_Setting__mdt ordSettings = (Compliance_Order_Setting__mdt) mOrdSettings.get(
							key
						);
						System.debug('ordSettings::' + ordSettings);
						if (ordSettings != null) {
							Schema.RecordTypeInfo toUpdateRecInfo = rtMapByName.get('HCP_Experience_Submitted');
							String submitRecordTypeId = toUpdateRecInfo.recordtypeid;
							o.RecordTypeId = submitRecordTypeId;
							if (o.ADC_Status__c != 'Pending') {
								o.ADC_Status__c = ordSettings.Final_Status__c;
							}
						}
					}
				}
			} else if (mAccToContract.containsKey(o.ADC_Contact_Name__c)) {
				o.addError('There is an existing HCP Wear Experience Order for this HCP');
			}
		}
	}

	//KK - HCP_Experience
	public static Map<String, Account> getHCPWearContract(Set<Id> accountIds) {
		Map<String, Account> mAccToContract = new Map<String, Account>();
		List<Account> laccount = [
			SELECT Id, FirstName, LastName, ADC_Has_HCP_Wear_Limit__c
			FROM Account
			WHERE ID IN :accountIds
		];

		System.debug('accountIds::' + accountIds);
		System.debug('laccount::' + laccount);
		for (Account a : laccount) {
			System.debug('ADC_Has_HCP_Wear_Limit__c->' + a.ADC_Has_HCP_Wear_Limit__c);
			if (a.ADC_Has_HCP_Wear_Limit__c) {
				if (mAccToContract.get(a.Id) == null) {
					mAccToContract.put(a.Id, a);
				}
			}
		}
		System.debug('getHCPContract->' + mAccToContract);
		return mAccToContract;
	}

	//KK - HCP_Experience
	public static boolean validateHCPWearLimit(
		List<ADC_Compliance_Order__c> compObjList,
		Map<String, Account> mAccToOrder,
		Map<String, List<ADC_Order_Product__c>> orderProductsList
	) {
		boolean valid = true;
		Map<String, Compliance_Order_Setting__mdt> lOrderSettings = mCompOrderSetting.get(HCP_EXPERIENCE_ORDER_TYPE);

		for (ADC_Compliance_Order__c compObj : compObjList) {
			if (mAccToOrder.containsKey(compObj.ADC_Contact_Name__c)) {
				compObj.addError(
					'There is an existing HCP Wear Experience Order for this HCP: ' + compObj.ADC_Contact_Name__r.Name
				);
				valid = false;
			}
			if (compObj.ADC_State__c == 'VT') {
				compObj.addError('Vermont is not an eligible state for HCP Wear Program');
				valid = false;
			}
		}
		return valid;
	}

	//KK - HCP_Experience
	public static Map<String, Map<String, List<ADC_HCP_Wear_Contracts__c>>> getHCPContracts() {
    // Outer map: Order Type -> (Product -> List of Contracts)
    Map<String, Map<String, List<ADC_HCP_Wear_Contracts__c>>> orderToProdToContract = new Map<String, Map<String, List<ADC_HCP_Wear_Contracts__c>>>();

    List<ADC_HCP_Wear_Contracts__c> lhcpContracts = [
        SELECT
            Id,
            Name,
            ADC_Begin_Date__c,
            ADC_End_Date__c,
            ADC_Allocation__c,
            ADC_Distributed_Quantity__c,
            ADC_LotOrSerial_Number__c,
            ADC_Product_Catalog__c,
            ADC_Remaining_Quantity__c,
            ADC_Order_type__c
        FROM ADC_HCP_Wear_Contracts__c
        WHERE ADC_Begin_Date__c <= TODAY AND ADC_End_Date__c >= TODAY AND ADC_Remaining_Quantity__c > 0
        FOR UPDATE
    ];

    for (ADC_HCP_Wear_Contracts__c c : lhcpContracts) {
        String orderType = c.ADC_Order_type__c;
        String product = c.ADC_Product_Catalog__c;

        if (!orderToProdToContract.containsKey(orderType)) {
            orderToProdToContract.put(orderType, new Map<String, List<ADC_HCP_Wear_Contracts__c>>());
        }

        Map<String, List<ADC_HCP_Wear_Contracts__c>> prodToContracts = orderToProdToContract.get(orderType);

        if (!prodToContracts.containsKey(product)) {
            prodToContracts.put(product, new List<ADC_HCP_Wear_Contracts__c>());
        }

        prodToContracts.get(product).add(c);
    }

    System.debug('orderToProdToContract -> ' + orderToProdToContract);
    return orderToProdToContract;
}

	private static void validateNCOWebSamplingOrders(
		List<ADC_Compliance_Order__c> lOrderList,
		Map<String, List<ADC_Order_Product__c>> mOrderToOrderProduct
	) {
		List<ADC_Compliance_Order__c> validOrders = new List<ADC_Compliance_Order__c>();
		for (ADC_Compliance_Order__c o : lOrderList) {
			if (validateProductQuantity(o, mOrderToOrderProduct.get(o.Id)).valid) {
				validOrders.add(o);
			}
		}

		for (ADC_Compliance_Order__c o : validOrders) {
			System.debug('o.ADC_Order_Type__c::' + o.ADC_Order_Type__c);
			Map<String, Compliance_Order_Setting__mdt> mOrdSettings = mCompOrderSetting.get(o.ADC_Order_Type__c);
			System.debug('mOrdSettings::' + mOrdSettings);

			Compliance_Order_Setting__mdt ordSettings = (Compliance_Order_Setting__mdt) mOrdSettings.get(
				o.ADC_Order_Type__c + ':' + o.ADC_Channel__c + ':Sensors'
			);
			System.debug('ordSettings::' + ordSettings);
			if (ordSettings == null) {
				ordSettings = (Compliance_Order_Setting__mdt) mOrdSettings.get(o.ADC_Order_Type__c + ':ALL:ALL');
			}
			System.debug('rtMapByName::' + rtMapByName);
			if (rtMapByName != null) {
				Schema.RecordTypeInfo toUpdateRecInfo = rtMapByName.get(ordSettings.Submit_Record_Type_API__c);
				String submitRecordTypeId = toUpdateRecInfo.recordtypeid;

				o.RecordTypeId = submitRecordTypeId;
				if (o.ADC_Status__c != 'Pending') {
					o.ADC_Status__c = ordSettings.Final_Status__c;
				}
			}
		}
	}

	public static Map<ADC_Compliance_Order__c, StatusWrapper> checkForHCPWearProduts(
		List<ADC_Compliance_Order__c> compObjList,
		Map<String, List<ADC_Order_Product__c>> orderProductsMap,
		List<ADC_HCP_Wear_Contracts__c> lhcpContracts
	) {
		System.debug('checkForHCPWearProduts::');

		Map<ADC_Compliance_Order__c, StatusWrapper> invalidOrders = new Map<ADC_Compliance_Order__c, StatusWrapper>();

		System.debug('lhcpContracts::' + lhcpContracts);
		Map<Id, List<ADC_HCP_Wear_Contracts__c>> hcpWearContractMap = new Map<Id, List<ADC_HCP_Wear_Contracts__c>>();
		for (ADC_HCP_Wear_Contracts__c contract : lhcpContracts) {
			if (hcpWearContractMap.get(contract.ADC_Product_Catalog__c) == null) {
				hcpWearContractMap.put(
					contract.ADC_Product_Catalog__c,
					new List<ADC_HCP_Wear_Contracts__c>{ contract }
				);
			} else {
				List<ADC_HCP_Wear_Contracts__c> contractsList = hcpWearContractMap.get(contract.ADC_Product_Catalog__c);
				contractsList.add(contract);
				hcpWearContractMap.put(contract.ADC_Product_Catalog__c, contractsList);
			}
		}

		System.debug('hcpWearContractMap::' + hcpWearContractMap);
		List<ADC_HCP_Wear_Contracts__c> lhcpContractstoUpdate = new List<ADC_HCP_Wear_Contracts__c>();
		List<ADC_Compliance_Order__c> lCompOrderstoUpdate = new List<ADC_Compliance_Order__c>();

		for (ADC_Compliance_Order__c compObj : compObjList) {
			ADC_Compliance_Order__c orderUpdate = compObj;
			orderUpdate.ADC_Packing_Instructions__c = null;

			List<ADC_Order_Product__c> orderProductList = orderProductsMap.get(compObj.Id);
			if (orderProductList != null) {
				for (ADC_Order_Product__c orderProduct : orderProductList) {
					if (!hcpWearContractMap.containsKey(orderProduct.ADC_Product__c)) {
						compObj.addError(
							orderProduct.ADC_Product__r.Name + ' is unavailable at this time to place an order'
						);
						invalidOrders.put(
							compObj,
							new StatusWrapper(
								false,
								String.format('Product is unavailable at this time.', new List<String>{ '', '' })
							)
						);
						continue;
					} else {
						List<ADC_HCP_Wear_Contracts__c> contractList = hcpWearContractMap.get(
							orderProduct.ADC_Product__c
						);
						if (orderUpdate.ADC_Packing_Instructions__c == null) {
							//AZ 2-28-24 - Update to append Labelled Lot
							orderUpdate.ADC_Packing_Instructions__c =
								'Labelled Lot ' + contractList[0].ADC_LotOrSerial_Number__c;
						} else {
							orderUpdate.ADC_Packing_Instructions__c += ', ' + contractList[0].ADC_LotOrSerial_Number__c;
						}

						/*ADC_HCP_Wear_Contracts__c contract = contractList[0];
                    contract.ADC_Remaining_Quantity__c = contract.ADC_Remaining_Quantity__c - 1;
                    contract.ADC_Distributed_Quantity__c = (contract.ADC_Distributed_Quantity__c == null) ? 0 : contract.ADC_Distributed_Quantity__c;
                    contract.ADC_Distributed_Quantity__c = contract.ADC_Distributed_Quantity__c + 1;
                    lhcpContractstoUpdate.add(contract);*/
					}
				}
			}
			System.debug('lCompOrderstoUpdate::' + lCompOrderstoUpdate);
			lCompOrderstoUpdate.add(orderUpdate);
		}
		System.debug('invalidOrders::' + invalidOrders);
		//update lCompOrderstoUpdate;
		//update lhcpContractstoUpdate;

		return invalidOrders;
	}

	public static Map<Id, Map<String, Sample_Limit_vod__c>> getHCPSampleLimits(Set<Id> hcpIds) {
		System.debug('** hcpIds: ' + hcpIds);
		Map<Id, Map<String, Sample_Limit_vod__c>> mAccToSampleLimit = new Map<Id, Map<String, Sample_Limit_vod__c>>();
		List<Sample_Limit_vod__c> lsampleLimit = [
			SELECT
				Id,
				Account_vod__c,
				Name,
				Sample_Limit_Type_vod__c,
				Start_Date_vod__c,
				End_Date_vod__c,
				Enforce_Limit_vod__c,
				Product_vod__c,
				Product_vod__r.ADC_Product_Group_Desc__c,
				Limit_Quantity_vod__c,
				Disbursed_Quantity_vod__c,
				Remaining_Quantity_vod__c
			FROM Sample_Limit_vod__c
			WHERE Account_vod__c IN :hcpIds AND Start_Date_vod__c <= TODAY AND End_Date_vod__c >= TODAY
		];
		for (Sample_Limit_vod__c sl : lsampleLimit) {
			Map<String, Sample_Limit_vod__c> mProdToSampleLimit = new Map<String, Sample_Limit_vod__c>();
			if (mAccToSampleLimit.containsKey(sl.Account_vod__c)) {
				if (mAccToSampleLimit.containsKey(sl.Account_vod__c)) {
					mProdToSampleLimit = mAccToSampleLimit.get(sl.Account_vod__c);
				}
			}
			mProdToSampleLimit.put(sl.Product_vod__r.ADC_Product_Group_Desc__c, sl);
			mAccToSampleLimit.put(sl.Account_vod__c, mProdToSampleLimit);
		}
		System.debug('mAccToSampleLimit->' + mAccToSampleLimit);
		return mAccToSampleLimit;
	}

	public static Map<Id, Map<String, ADC_Compliance_Order_Contract__c>> getContract(Set<Id> accountIds) {
		System.debug('** contract acc Ids: ' + accountIds);
		Map<Id, Map<String, ADC_Compliance_Order_Contract__c>> mAccToContract = new Map<Id, Map<String, ADC_Compliance_Order_Contract__c>>();
		List<ADC_Compliance_Order_Contract__c> lcontract = [
			SELECT
				Id,
				ADC_Account__c,
				Name,
				ADC_Begin_Date__c,
				ADC_End_Date__c,
				ADC_Allocation__c,
				ADC_Distributed_Quantity__c,
				ADC_Product__c
			FROM ADC_Compliance_Order_Contract__c
			WHERE ADC_Account__c IN :accountIds AND ADC_Begin_Date__c <= TODAY AND ADC_End_Date__c >= TODAY
		];
		for (ADC_Compliance_Order_Contract__c c : lcontract) {
			Map<String, ADC_Compliance_Order_Contract__c> mProdToContract = new Map<String, ADC_Compliance_Order_Contract__c>();
			if (mAccToContract.containsKey(c.ADC_Account__c)) {
				mProdToContract = mAccToContract.get(c.ADC_Account__c);
			}
			mProdToContract.put(c.ADC_Product__c, c);
			mAccToContract.put(c.ADC_Account__c, mProdToContract);
		}
		System.debug('mAccToContract->' + mAccToContract);
		return mAccToContract;
	}

	public static List<ADC_Compliance_Order__c> validateInProgressOrderExists(List<ADC_Compliance_Order__c> newItems) {
		System.debug('validateInProgressOrderExists::');

		List<ADC_Compliance_Order__c> validOrders = new List<ADC_Compliance_Order__c>();
		Map<String, List<ADC_Compliance_Order__c>> mKeyToCO = new Map<String, List<ADC_Compliance_Order__c>>();
		Map<String, Set<Id>> hcoIds = new Map<String, Set<Id>>();
		Map<String, Set<Id>> hcpIds = new Map<String, Set<Id>>();

		Map<String, Compliance_Existing_Order_Rules__mdt> mRules = new Map<String, Compliance_Existing_Order_Rules__mdt>();

		for (ADC_Compliance_Order__c o : newItems) {
			string key = o.ADC_Order_Type__c + ':' + o.ADC_Channel__c;
			System.debug('key::' + key);
			Compliance_Existing_Order_Rules__mdt rule = mExistingOrderRules.get(key);
			System.debug('rule::' + rule);
			if (
				rule != null &&
				(!rule.Bypass_Rule_for_Compliance_Team__c ||
				(rule.Bypass_Rule_for_Compliance_Team__c && isComplianceTeamMember()))
			) {
				mRules.put(key, rule);
				if (rule.HCO__c && o.ADC_Account_Name__c != null) {
					Set<Id> tmp = new Set<Id>();
					if (hcoIds.containsKey(key)) {
						tmp = hcoIds.get(key);
					}
					tmp.add(o.ADC_Account_Name__c);
					hcoIds.put(key, tmp);
				}
				if (rule.HCP__c && o.ADC_Contact_Name__c != null) {
					Set<Id> tmp = new Set<Id>();
					if (hcpIds.containsKey(key) && hcoIds.get(key) != null) {
						tmp = hcoIds.get(key);
					}
					System.debug('key::' + key);
					System.debug('tmp::' + tmp);
					System.debug('hcpIds::' + hcpIds);
					System.debug('o.ADC_Contact_Name__c::' + o.ADC_Contact_Name__c);
					if (tmp == null) {
						tmp = new Set<Id>();
						tmp.add(o.ADC_Contact_Name__c);
					}
					hcpIds.put(key, tmp);
				}
			}
		}
		System.debug('** hcpIds: ' + hcpIds + '\nhcoIds:' + hcoIds);

		Map<String, Integer> mCount = new Map<String, Integer>();
		Map<String, String[]> mruleFields = new Map<String, String[]>();
		for (Compliance_Existing_Order_Rules__mdt rule : mRules.values()) {
			string key = rule.Order_Type__c + ':' + rule.Channel__c;
			List<String> lstatus = rule.Status__c.split(',');

			String fields = 'ADC_Channel__c,ADC_Order_Type__c';
			String whereStr =
				'ADC_Channel__c=\'' +
				rule.Channel__c +
				'\' AND ADC_Order_Type__c=\'' +
				rule.Order_Type__c +
				'\'  AND ADC_Status__c in :lstatus';
			Set<Id> lhcoId = hcoIds.get(key);
			Set<Id> lhcpId = hcpIds.get(key);

			if (rule.HCO__c) {
				fields = fields + ',ADC_Account_Name__c';
				whereStr = whereStr + ' AND ADC_Account_Name__c in :lhcoId';
			}
			if (rule.HCP__c) {
				fields = fields + ',ADC_Contact_Name__c';
				whereStr = whereStr + ' AND ADC_Contact_Name__c in :lhcpId';
			}
			if (rule.Address__c) {
				fields = fields + ',ADC_Address_Line_1__c,ADC_City__c,ADC_State__c,ADC_Zip_Code__c';
			}
			String[] lflds = fields.split(',');
			mruleFields.put(key, lflds);
			String qry =
				'SELECT ' +
				fields +
				',count(Id) FROM ADC_Compliance_Order__c WHERE ' +
				whereStr +
				' GROUP BY ' +
				fields;
			AggregateResult[] groupedResults = Database.query(qry);

			System.debug('** qry: ' + qry + '\ngroupedResults:' + groupedResults);
			System.debug('** lhcoId: ' + lhcoId + ', lhcpId: ' + lhcpId + ', status IN : ' + lstatus);

			for (AggregateResult ar : groupedResults) {
				String fldkey = '';
				for (string fld : lflds) {
					fldkey = fldkey + ':' + ar.get(fld);
				}
				Integer val = (Integer) ar.get('expr0');
				mCount.put(fldkey, val);
			}
		}
		System.debug('** mCount: ' + mCount);

		for (ADC_Compliance_Order__c o : newItems) {
			string key = o.ADC_Order_Type__c + ':' + o.ADC_Channel__c;
			String[] lflds = (String[]) mruleFields.get(key);

			Integer count = 0;
			if (lflds != null) {
				String fieldKey = '';
				for (String fld : lflds) {
					fieldKey = fieldKey + ':' + o.get(fld);
				}
				count = mCount.get(fieldKey);
			}

			if (count != null && count > 0) {
				o.addError(Label.VPRO_ExistingOrderInProgressMsg);
			} else {
				validOrders.add(o);
			}
		}

		System.debug('** validOrders: ' + validOrders);

		return validOrders;
	}

	public static void validateVAAddress(List<ADC_Compliance_Order__c> lorders, Set<Id> hcpIds) {
		Map<id, List<Address_vod__c>> mAccToAddr = new Map<id, List<Address_vod__c>>();
		List<Address_vod__c> lAddr = [
			SELECT Id, Account_vod__c
			FROM address_vod__c
			WHERE Account_vod__c IN :hcpIds AND License_Validation__c = 'TRUE' AND State_vod__c = 'VT'
		];
		for (Address_vod__c a : lAddr) {
			List<Address_vod__c> tmpList = new List<Address_vod__c>();
			if (mAccToAddr.containsKey(a.Account_vod__c)) {
				tmpList = mAccToAddr.get(a.Account_vod__c);
			}
			tmpList.add(a);
			mAccToAddr.put(a.Account_vod__c, tmpList);
		}
		System.debug('** lorders:' + lorders);
		for (ADC_Compliance_Order__c o : lorders) {
			if (mAccToAddr.containsKey(o.ADC_Contact_Name__c)) {
				o.addError('You cannot create order as this HCP has Vermont state license. ');
			}
		}
	}

	public static boolean verifySampleLimitHasBeenSet(
		List<ADC_Compliance_Order__c> lorders,
		Map<Id, Map<String, Sample_Limit_vod__c>> mAccToSampleLimit
	) {
		boolean valid = true;

		for (ADC_Compliance_Order__c o : lorders) {
			Map<Id, List<Sample_Limit_vod__c>> mProdToSampleLimit = null;
			if (!mAccToSampleLimit.containsKey(o.ADC_Contact_Name__c)) {
				o.addError('No Sample Limit has been set for this HCP');
				valid = false;
				continue;
			}
		}
		return valid;
	}

	public static boolean verifyContractExists(
		List<ADC_Compliance_Order__c> lorders,
		Map<Id, Map<String, ADC_Compliance_Order_Contract__c>> mAccToContract
	) {
		boolean valid = true;

		for (ADC_Compliance_Order__c o : lorders) {
			Map<Id, List<ADC_Compliance_Order_Contract__c>> mProdToContrcatLimit = null;
			if (!mAccToContract.containsKey(o.ADC_Account_Name__c)) {
				o.addError('No Contract exists for this Account');
				valid = false;
				continue;
			}
		}
		return valid;
	}

	public static Map<String, Map<Id, Map<String, Map<String, Decimal>>>> createAccountCountMap(
		ADC_Order_Product__c op,
		Map<String, Map<Id, Map<String, Map<String, Decimal>>>> mOrderTypeToAccCount
	) {
		id acc = null;
		if (
			op.ADC_Order_Type__c == BRAND_DEVELOPMENT_ORDER_TYPE ||
			op.ADC_Order_Type__c == CHARITABLE_DONATIONS_ORDER_TYPE ||
			op.ADC_Order_Type__c == EVALUATION_CGM_ORDER_TYPE
		) {
			return mOrderTypeToAccCount;
		}
		if (
			op.ADC_Order_Type__c == MANAGEMENT_ORDER_CGM_ORDER_TYPE &&
			(op.ADC_Order__r.ADC_Channel__c == 'HCP' ||
			op.ADC_Order__r.ADC_Channel__c == 'Market Access')
		) {
			acc = op.ADC_Order__r.ADC_Contact_Name__c;
		} else {
			acc = (op.ADC_Order_Type__c == DATA_CABLE_REQUEST_ORDER_TYPE ||
				op.ADC_Order_Type__c == SENSING_EDUCATION_ITEMS_ORDER_TYPE)
				? op.ADC_Order__r.ADC_Contact_Name__c
				: op.ADC_Order__r.ADC_Account_Name__c;
		}

		if (op.ADC_Quantity__c != null) {
			Map<Id, Map<String, Map<String, Decimal>>> mTmpOrderTypeToAccCount = new Map<Id, Map<String, Map<String, Decimal>>>();
			if (mOrderTypeToAccCount.containsKey(op.ADC_Order_Type__c)) {
				mTmpOrderTypeToAccCount = mOrderTypeToAccCount.get(op.ADC_Order_Type__c);
			}

			Map<String, Map<String, Decimal>> mTmpAccountToChannelCount = new Map<String, Map<String, Decimal>>();
			if (mTmpOrderTypeToAccCount.containsKey(acc)) {
				mTmpAccountToChannelCount = mTmpOrderTypeToAccCount.get(acc);
			}

			//Set Value at the Account Level (All Channel)
			Decimal totalAccVal = 0;
			Map<String, Decimal> mTmpAllChannelProductGrpToCount = new Map<String, Decimal>();
			if (mTmpAccountToChannelCount.containsKey('ALL')) {
				mTmpAllChannelProductGrpToCount = mTmpAccountToChannelCount.get('ALL');
			}
			Map<String, Decimal> mTmpProductGrpToCount = new Map<String, Decimal>();
			if (mTmpAccountToChannelCount.containsKey(op.ADC_Order__r.ADC_Channel__c)) {
				mTmpProductGrpToCount = mTmpAccountToChannelCount.get(op.ADC_Order__r.ADC_Channel__c);
			}
			if (op.ADC_Order_Type__c == CONTRACTED_CUSTOMER_ORDER_TYPE) {
				if (op.ADC_Product__c != null) {
					Decimal val = 0;
					Decimal allval = 0;
					if (mTmpProductGrpToCount.containsKey(op.ADC_Product__c)) {
						val = mTmpProductGrpToCount.get(op.ADC_Product__c);
					}
					mTmpProductGrpToCount.put(op.ADC_Product__c, val + op.ADC_Quantity__c);
				}
			} else {
				if (op.ADC_Product__r.ADC_Product_Group_Desc__c != null) {
					Decimal val = 0;
					Decimal allval = 0;
					if (mTmpProductGrpToCount.containsKey(op.ADC_Product__r.ADC_Product_Group_Desc__c)) {
						val = mTmpProductGrpToCount.get(op.ADC_Product__r.ADC_Product_Group_Desc__c);
					}
					if (mTmpAllChannelProductGrpToCount.containsKey(op.ADC_Product__r.ADC_Product_Group_Desc__c)) {
						allval = mTmpAllChannelProductGrpToCount.get(op.ADC_Product__r.ADC_Product_Group_Desc__c);
					}
					mTmpProductGrpToCount.put(op.ADC_Product__r.ADC_Product_Group_Desc__c, val + op.ADC_Quantity__c);
					mTmpAllChannelProductGrpToCount.put(
						op.ADC_Product__r.ADC_Product_Group_Desc__c,
						allval + op.ADC_Quantity__c
					);
				}
			}

			//set group value at each channel level
			Decimal totalval = 0;
			if (mTmpProductGrpToCount.containsKey('ALL')) {
				totalval = mTmpProductGrpToCount.get('ALL');
			}
			mTmpProductGrpToCount.put('ALL', totalval + op.ADC_Quantity__c);
			//set group value at each allchannel level
			Decimal alltotalval = 0;
			if (mTmpAllChannelProductGrpToCount.containsKey('ALL')) {
				totalval = mTmpAllChannelProductGrpToCount.get('ALL');
			}
			mTmpAllChannelProductGrpToCount.put('ALL', alltotalval + op.ADC_Quantity__c);

			mTmpAccountToChannelCount.put(op.ADC_Order__r.ADC_Channel__c, mTmpProductGrpToCount);
			mTmpAccountToChannelCount.put('ALL', mTmpAllChannelProductGrpToCount);
			mTmpOrderTypeToAccCount.put(acc, mTmpAccountToChannelCount);
			mOrderTypeToAccCount.put(op.ADC_Order_Type__c, mTmpOrderTypeToAccCount);
		}

		return mOrderTypeToAccCount;
	}

	private static void validateAddress(ADC_Compliance_Order__c o) {
		if (
			(o.ADC_Address_Line_1__c != null && o.ADC_Address_Line_1__c.length() > 30) ||
			(o.ADC_Address_Line_2__c != null &&
			o.ADC_Address_Line_2__c.length() > 30)
		) {
			o.ADC_Status__c = 'Pending';
			o.Pending_Message__c = 'Address is greater than 30 characters';
		}
	}

	//AZ - Adding second validation for email domains that are not @ihs.gov, @mil.com, or @va.gov
	private static void validateEmail(ADC_Compliance_Order__c o) {
		if (o.ADC_Requires_Compliance_Review__c == true && o.ADC_Order_Type__c == HCP_EXPERIENCE_ORDER_TYPE) {
			o.ADC_Status__c = 'Pending';
			o.ADC_Requires_Compliance_Review__c = false;
			o.Pending_Message__c = 'Email domain requires Compliance review';
		}
	}

	private static void validateGenericOrders(
		List<ADC_Compliance_Order__c> lOrderList,
		Map<String, List<ADC_Order_Product__c>> mOrderToOrderProduct
	) {
		List<ADC_Compliance_Order__c> validOrders = new List<ADC_Compliance_Order__c>();
		for (ADC_Compliance_Order__c o : lOrderList) {
			if (validateProductQuantity(o, mOrderToOrderProduct.get(o.Id)).valid) {
				validOrders.add(o);
			}
		}

		for (ADC_Compliance_Order__c o : validOrders) {
			System.debug('o.ADC_Order_Type__c::' + o.ADC_Order_Type__c);
			Map<String, Compliance_Order_Setting__mdt> mOrdSettings = mCompOrderSetting.get(o.ADC_Order_Type__c);
			System.debug('mOrdSettings::' + mOrdSettings);

			Compliance_Order_Setting__mdt ordSettings = (Compliance_Order_Setting__mdt) mOrdSettings.get(
				o.ADC_Order_Type__c + ':' + o.ADC_Channel__c + ':ALL'
			);
			if (ordSettings == null) {
				ordSettings = (Compliance_Order_Setting__mdt) mOrdSettings.get(o.ADC_Order_Type__c + ':ALL:ALL');
			}
			System.debug('rtMapByName::' + rtMapByName);
			if (rtMapByName != null) {
				Schema.RecordTypeInfo toUpdateRecInfo = rtMapByName.get(ordSettings.Submit_Record_Type_API__c);
				String submitRecordTypeId = toUpdateRecInfo.recordtypeid;

				o.RecordTypeId = submitRecordTypeId;
				if (o.ADC_Status__c != 'Pending') {
					o.ADC_Status__c = ordSettings.Final_Status__c;
				}
			}
		}
	}

	private static void validateDataCableRequest(
		List<ADC_Compliance_Order__c> lOrderList,
		Map<String, List<ADC_Order_Product__c>> mOrderToOrderProduct,
		Map<String, Map<Id, Map<String, Map<String, Decimal>>>> mOrderTypeToAccCount
	) {
		Map<String, Compliance_Order_Setting__mdt> mOrdSettings = mCompOrderSetting.get(DATA_CABLE_REQUEST_ORDER_TYPE);

		Map<Id, Map<String, Map<String, Decimal>>> mAccToOrderCount = mOrderTypeToAccCount.get(
			DATA_CABLE_REQUEST_ORDER_TYPE
		);
		System.debug('mAccToOrderCount->' + mAccToOrderCount);
		List<ADC_Compliance_Order__c> validOrders = new List<ADC_Compliance_Order__c>();
		Map<Id, List<ADC_Compliance_Order__c>> mAccToOrder = new Map<Id, List<ADC_Compliance_Order__c>>();
		for (ADC_Compliance_Order__c o : lOrderList) {
			if (validateProductQuantity(o, mOrderToOrderProduct.get(o.Id)).valid) {
				validOrders.add(o);
				List<ADC_Compliance_Order__c> ltmp = new List<ADC_Compliance_Order__c>();
				if (mAccToOrder.containsKey(o.ADC_Contact_Name__c)) {
					ltmp = mAccToOrder.get(o.ADC_Contact_Name__c);
				}
				ltmp.add(o);
				mAccToOrder.put(o.ADC_Contact_Name__c, lTmp);
			}
		}
		Map<ADC_Compliance_Order__c, StatusWrapper> invalidOrders = new Map<ADC_Compliance_Order__c, StatusWrapper>();
		if (lOrderTypeWithAnnualLimit.contains(DATA_CABLE_REQUEST_ORDER_TYPE)) {
			invalidOrders = validateAnnualLimit(
				DATA_CABLE_REQUEST_ORDER_TYPE,
				mAccToOrder,
				mAccToOrderCount,
				null,
				false,
				mOrderToOrderProduct
			);
		}
		for (ADC_Compliance_Order__c o : validOrders) {
			if (!invalidOrders.containsKey(o)) {
				Compliance_Order_Setting__mdt ordSettings = (Compliance_Order_Setting__mdt) mOrdSettings.get(
					DATA_CABLE_REQUEST_ORDER_TYPE + ':' + o.ADC_Channel__c + ':ALL'
				);
				if (ordSettings == null) {
					ordSettings = (Compliance_Order_Setting__mdt) mOrdSettings.get(
						DATA_CABLE_REQUEST_ORDER_TYPE + ':ALL:ALL'
					);
				}
				Schema.RecordTypeInfo toUpdateRecInfo = rtMapByName.get(ordSettings.Submit_Record_Type_API__c);
				String submitRecordTypeId = toUpdateRecInfo.recordtypeid;

				o.RecordTypeId = submitRecordTypeId;
				if (o.ADC_Status__c != 'Pending') {
					o.ADC_Status__c = ordSettings.Final_Status__c;
				}
			}
		}
	}

	public static Map<ADC_Compliance_Order__c, StatusWrapper> validateContractLimit(
		Map<Id, List<ADC_Compliance_Order__c>> mAccToOrder,
		Map<Id, Map<String, Map<String, Decimal>>> mAccToOrderCount,
		Map<Id, Map<String, ADC_Compliance_Order_Contract__c>> mAccToContract
	) {
		Map<ADC_Compliance_Order__c, StatusWrapper> invalidOrders = new Map<ADC_Compliance_Order__c, StatusWrapper>();
		map<String, Compliance_Order_Setting__mdt> lOrderSettings = mCompOrderSetting.get(
			CONTRACTED_CUSTOMER_ORDER_TYPE
		);
		for (String accId : mAccToOrder.keySet()) {
			List<ADC_Compliance_Order__c> lOrders = mAccToOrder.get(accId);
			Map<String, Map<String, Decimal>> mChannelCount = mAccToOrderCount.get(accId);
			System.debug('mAccToContract-->' + mAccToContract);
			Map<String, ADC_Compliance_Order_Contract__c> mProdToLimit = mAccToContract.get(accId);
			for (ADC_Compliance_Order__c o : lOrders) {
				System.debug('mProdToLimit-->' + mProdToLimit);
				if (mProdToLimit == null) {
					o.addError('No contract exists for this account');
					invalidOrders.put(o, new StatusWrapper(false, 'No contract for this account'));
					continue;
				}
				Map<String, Decimal> mProductToCount = mChannelCount.get(o.ADC_Channel__c);
				Compliance_Order_Setting__mdt ordSettings = lOrderSettings.get(
					CONTRACTED_CUSTOMER_ORDER_TYPE + ':' + o.ADC_Channel__c + ':ALL'
				);
				for (String prod : mProductToCount.keySet()) {
					if (prod == 'ALL') {
						continue;
					}
					Decimal qnty = (Decimal) mProductToCount.get(prod);
					System.debug('qnty-->' + qnty);
					if (qnty != null && !bypassValidationForComplianceTeam(ordSettings)) {
						ADC_Compliance_Order_Contract__c contract = mProdToLimit.get(prod);
						if (contract == null) {
							System.debug('here contract-->' + prod + 'sl' + contract);
							o.addError('No contract exist for this Account for the product');
							invalidOrders.put(
								o,
								new StatusWrapper(false, 'No contract exist for this Account for the product')
							);
							continue;
						}
						Decimal yearLimit = contract.ADC_Allocation__c - contract.ADC_Distributed_Quantity__c;
						if (yearLimit != null) {
							if (qnty > yearLimit) {
								if (ordSettings.Send_to_pending__c == true) {
									o.ADC_Status__c = 'Pending';
									o.Pending_Message__c = String.format(
										Label.VPRO_DataCableYearLImitMsg,
										new List<String>{
											'' + contract.ADC_Distributed_Quantity__c,
											'' + qnty,
											'' + contract.ADC_Allocation__c
										}
									);
								} else {
									o.addError(
										String.format(
											Label.VPRO_DataCableYearLImitMsg,
											new List<String>{
												'' + contract.ADC_Distributed_Quantity__c,
												'' + qnty,
												'' + contract.ADC_Allocation__c
											}
										)
									);
									invalidOrders.put(
										o,
										new StatusWrapper(
											false,
											String.format(
												Label.VPRO_DataCableYearLImitMsg,
												new List<String>{
													'' + contract.ADC_Distributed_Quantity__c,
													'' + qnty,
													'' + contract.ADC_Allocation__c
												}
											)
										)
									);
								}
							}
						}
					}
				}
			}
		}
		return invalidOrders;
	}

	public static Map<ADC_Compliance_Order__c, StatusWrapper> validateAnnualSampleLimit(
		Map<Id, List<ADC_Compliance_Order__c>> mAccToOrder,
		Map<Id, Map<String, Map<String, Decimal>>> mAccToOrderCount,
		Map<Id, Map<String, Sample_Limit_vod__c>> mAccToSampleLimit
	) {
		Map<ADC_Compliance_Order__c, StatusWrapper> invalidOrders = new Map<ADC_Compliance_Order__c, StatusWrapper>();
		// Get the Compliance Order Settings
		map<String, Compliance_Order_Setting__mdt> lOrderSettings = mCompOrderSetting.get(
			MANAGEMENT_ORDER_CGM_ORDER_TYPE
		);
		for (String accId : mAccToOrder.keySet()) {
			List<ADC_Compliance_Order__c> lOrders = mAccToOrder.get(accId);
			Map<String, Map<String, Decimal>> mChannelCount = mAccToOrderCount.get(accId);

			System.debug('** lOrderSettings: ' + lOrderSettings);
			System.debug('** keyset: ' + lOrderSettings.keySet());

			for (ADC_Compliance_Order__c o : lOrders) {
				if (!lOrderSettings.isEmpty()) {
					for (string key : lOrderSettings.keySet()) {
						String[] str = key.split(':');
						String ordType = str[0];
						String channel = str[1];
						String prodGroup = str[2];
						System.debug('o.ADC_Channel__c -->' + o.ADC_Channel__c);
						System.debug('key-->' + key);
						Sample_Limit_vod__c sl;
						if (o.ADC_Channel__c == channel) {
							Compliance_Order_Setting__mdt ordSettings = lOrderSettings.get(key);
							Map<String, Decimal> mProductGrpCount = mChannelCount.get(channel);
							Decimal qnty = mProductGrpCount.get(prodGroup);
							if (qnty != null && !bypassValidationForComplianceTeam(ordSettings)) {
								Decimal totalQuantity = qnty;
								Decimal yearLimit = null;
								System.debug('** mAccToSampleLimit-->' + mAccToSampleLimit);
								Map<String, Sample_Limit_vod__c> mProdToLimit = mAccToSampleLimit.get(accId);

								if (mProdToLimit == null) {
									o.addError('No Sample Limit has been set for this HCP');
									invalidOrders.put(
										o,
										new StatusWrapper(false, 'No sample limit is set for this HCP')
									);
									continue;
								}
								System.debug('mProdToLimit-->' + mProdToLimit);
								System.debug('prodGroup-->' + prodGroup);

								if (mProdToLimit != null && prodGroup != 'ALL') {
									System.debug('prodGroup-->' + prodGroup);
									sl = mProdToLimit.get(prodGroup);
									System.debug('sl-->' + sl);
									if (sl == null) {
										System.debug('here sl-->' + prodGroup + 'sl' + sl);
										o.addError(
											'No Sample Limit has been set for this HCP for the selected product'
										);
										invalidOrders.put(
											o,
											new StatusWrapper(
												false,
												'No sample limit is set for this HCP for the product'
											)
										);
										continue;
									}
									yearLimit = sl.Remaining_Quantity_vod__c;
								}

								System.debug('qnty-->' + qnty);
								if (yearLimit != null) {
									if (prodGroup != 'ALL') {
										if (mProductGrpCount.containsKey(prodGroup)) {
											if (totalQuantity > yearLimit) {
												if (ordSettings.Send_to_pending__c == true) {
													o.ADC_Status__c = 'Pending';
													o.Pending_Message__c = String.format(
														Label.VPRO_DataCableYearLImitMsg,
														new List<String>{
															'' + sl.Disbursed_Quantity_vod__c,
															'' + qnty,
															'' + sl.Limit_Quantity_vod__c
														}
													);
												} else {
													o.addError(
														String.format(
															Label.VPRO_DataCableYearLImitMsg,
															new List<String>{
																'' + sl.Disbursed_Quantity_vod__c,
																'' + qnty,
																'' + sl.Limit_Quantity_vod__c
															}
														)
													);
													invalidOrders.put(
														o,
														new StatusWrapper(
															false,
															String.format(
																Label.VPRO_DataCableYearLImitMsg,
																new List<String>{
																	'' + sl.Disbursed_Quantity_vod__c,
																	'' + qnty,
																	'' + sl.Limit_Quantity_vod__c
																}
															)
														)
													);
												}
											}
										}
									}
								}
							}
						}
					}
				}
			}
		}

		return invalidOrders;
	}

	public static Map<ADC_Compliance_Order__c, StatusWrapper> validateAnnualLimit(
		String OrderType,
		Map<Id, List<ADC_Compliance_Order__c>> mAccToOrder,
		Map<Id, Map<String, Map<String, Decimal>>> mAccToOrderCount,
		map<Id, Decimal> mAccLimit,
		boolean accLimitSendToPending,
		Map<String, List<ADC_Order_Product__c>> mOrderToOrderProduct
	) {
		Map<ADC_Compliance_Order__c, StatusWrapper> invalidOrders = new Map<ADC_Compliance_Order__c, StatusWrapper>();
		Integer currentYear = System.Today().year();
		AggregateResult[] groupedResults = null;
		System.debug('mAccToOrder in method-->' + mAccToOrder);
		System.debug('mAccToOrderCount in method-->' + mAccToOrderCount);
		if (OrderType == DATA_CABLE_REQUEST_ORDER_TYPE || OrderType == SENSING_EDUCATION_ITEMS_ORDER_TYPE) {
			groupedResults = [
				SELECT
					ADC_Order__r.ADC_Contact_Name__c acc,
					ADC_Order__r.ADC_Channel__c channel,
					ADC_Product__r.ADC_Product_Group_Desc__c prodDesc,
					SUM(ADC_Quantity__c) totalQnty,
					MAX(ADC_Order__r.ADC_Order_Date__c) latestOrder
				FROM ADC_Order_Product__c
				WHERE
					CALENDAR_YEAR(CreatedDate) = :currentYear
					AND ADC_Order__r.ADC_Status__c NOT IN ('Draft', 'Cancel', 'Returned')
					AND ADC_Order__r.ADC_Order_Type__c = :OrderType
					AND ADC_Order__r.ADC_Contact_Name__c IN :mAccToOrder.keySet()
					AND ADC_Product__r.External_ID_vod__c != :VPRO_ComplianceOrderValidator.TAndCProductCode
				GROUP BY ROLLUP(
					ADC_Order__r.ADC_Contact_Name__c,
					ADC_Order__r.ADC_Channel__c,
					ADC_Product__r.ADC_Product_Group_Desc__c
				)
			];
		} else {
			System.debug('** orderType: ' + OrderType);
			groupedResults = [
				SELECT
					ADC_Order__r.ADC_Account_Name__c acc,
					ADC_Order__r.ADC_Channel__c channel,
					ADC_Product__r.ADC_Product_Group_Desc__c prodDesc,
					SUM(ADC_Quantity__c) totalQnty,
					MAX(ADC_Order__r.ADC_Order_Date__c) latestOrder
				FROM ADC_Order_Product__c
				WHERE
					CALENDAR_YEAR(CreatedDate) = :currentYear
					AND ADC_Order__r.ADC_Status__c NOT IN ('Draft', 'Cancel', 'Returned')
					AND ADC_Order__r.ADC_Order_Type__c = :OrderType
					AND ADC_Order__r.ADC_Account_Name__c IN :mAccToOrder.keySet()
					AND ADC_Product__r.External_ID_vod__c != :VPRO_ComplianceOrderValidator.TAndCProductCode
				GROUP BY ROLLUP(
					ADC_Order__r.ADC_Account_Name__c,
					ADC_Order__r.ADC_Channel__c,
					ADC_Product__r.ADC_Product_Group_Desc__c
				)
			];
		}
		map<String, Compliance_Order_Setting__mdt> lOrderSettings = mCompOrderSetting.get(orderType);

		Map<Id, List<AggregateResult>> mAccToGroupResult = new Map<Id, List<AggregateResult>>();
		// Map of existing orders. Key=accountId:Channel:ProductDesc, value=Qty
		Map<String, Decimal> mAccToCount = new Map<String, Decimal>();
		Map<String, Date> mAccToDate = new Map<String, Date>();
		System.debug('** groupedResults: ' + groupedResults);
		for (AggregateResult ar : groupedResults) {
			String accId = (String) ar.get('acc');
			String channel = (String) (ar.get('channel') != null ? ar.get('channel') : 'ALL');
			String productDesc = (String) (ar.get('prodDesc') != null ? ar.get('prodDesc') : 'ALL');
			String key = accId + ':' + channel + ':' + productDesc;
			Decimal qnty = (Decimal) ar.get('totalQnty');
			Date latestOrder = (Date) ar.get('latestOrder');
			mAccToCount.put(key, qnty);
			mAccToDate.put(key, latestOrder);
		}
		System.debug('** mAccToCount->' + mAccToCount);
		System.debug('** mAccToDate->' + mAccToDate);
		for (String accId : mAccToOrder.keySet()) {
			List<ADC_Compliance_Order__c> lOrders = mAccToOrder.get(accId);
			Map<String, Map<String, Decimal>> mChannelCount = mAccToOrderCount.get(accId);

			for (ADC_Compliance_Order__c o : lOrders) {
				if (!lOrderSettings.isEmpty()) {
					for (string key : lOrderSettings.keySet()) {
						String[] str = key.split(':');
						String ordType = str[0];
						String channel = str[1];
						String prodGroup = str[2];
						System.debug('** o.ADC_Channel__c -->' + o.ADC_Channel__c);
						System.debug('** key-->' + key);
						System.debug('** lOrderSettings-->' + lOrderSettings);

						if (o.ADC_Channel__c == channel || channel == 'ALL') {
							Compliance_Order_Setting__mdt ordSettings = lOrderSettings.get(key);

							Decimal accTotalQnty = mAccToCount.get(accId + ':' + channel + ':' + prodGroup);
							if (accTotalQnty == null) {
								accTotalQnty = mAccToCount.get(accId + ':' + o.ADC_Channel__c + ':' + prodGroup) != null
									? mAccToCount.get(accId + ':' + o.ADC_Channel__c + ':' + prodGroup)
									: 0.0;
							}

							/*
                            // Consider the previously placed orders of ADDTL_DEMOKIT_PRODUCT_DESC (e.g. Demo Kit 14 Day)
                            if (prodGroup == 'Demo Kit 2 Day') {
                                Decimal addtlQty = mAccToCount.get(accId+':'+o.ADC_Channel__c+':'+ADDTL_DEMOKIT_PRODUCT_DESC)!=null ? mAccToCount.get(accId+':'+o.ADC_Channel__c+':'+ADDTL_DEMOKIT_PRODUCT_DESC):0.0 ;
                                System.debug('** Qty from Additonal Demokit Product Desc: ' + addtlQty);
                                accTotalQnty += addtlQty;
                            }
                            */

							Date latestOrder = mAccToDate.get(accId + ':' + channel + ':' + prodGroup);
							System.debug('accTotalQnty -->' + accTotalQnty);
							Map<String, Decimal> mProductGrpCount = mChannelCount.get(channel);
							System.debug('mProductGrpCount -->' + mProductGrpCount);
							Decimal qnty = mProductGrpCount.get(prodGroup);
							System.debug('qnty -->' + qnty);
							if (
								qnty != null &&
								!bypassValidationForComplianceTeam(ordSettings) &&
								(ordSettings.Non_Physical__c == true &&
								isNonPhysical(o, mOrderToOrderProduct.get(o.id)) ||
								ordSettings.Non_Physical__c == false)
							) {
								Decimal totalQuantity = accTotalQnty + qnty;
								System.debug('** totalQuantity: ' + totalQuantity);
								System.debug(
									'** ordSettings.Per_Year_Limit_Account_Field_Name__c: ' +
									ordSettings.Per_Year_Limit_Account_Field_Name__c
								);
								System.debug(
									'** ordSettings.OverrideAccountLevel__c: ' + ordSettings.OverrideAccountLevel__c
								);

								Decimal yearLimit = null;
								if (
									ordSettings.OverrideAccountLevel__c &&
									ordSettings.Per_Year_Limit_Account_Field_Name__c != null
								) {
									yearLimit = mAccLimit.get(accId) != null ? mAccLimit.get(accId) : 0.0;
									System.debug('**1 set yearLimit: ' + mAccLimit.get(accId));
								} else if (ordSettings.Per_Year_Limit__c != null) {
									System.debug('**2 set yearLimit: ' + ordSettings.Per_Year_Limit__c);
									yearLimit = ordSettings.Per_Year_Limit__c;
								}
								System.debug('mAccLimit -->' + mAccLimit);
								System.debug('yearLimit -->' + yearLimit);

								// Per Year Limit is set. Check against Per Year Limit
								if (yearLimit != null) {
									System.debug(
										'** prodGroup: ' +
											prodGroup +
											', totalQuantity: ' +
											totalQuantity +
											', yearLimit: ' +
											yearLimit
									);
									System.debug(
										'** mProductGrpCount: ' +
											mProductGrpCount +
											', ' +
											mProductGrpCount.containsKey(prodGroup)
									);

									// SC. 07/30/2020
									// Add quantity from orders of PREV_DEMOKIT_PRODUCT_DESC (e.g. Demo Kit 14 Day) previously placed this year
									//if (prodGroup == 'Demo Kit 2 Day') {
									if (prodGroup == CURRENT_DEMOKIT_PRODUCT_DESC) {
										for (String prodDesc : PREV_DEMOKIT_PRODUCT_DESC) {
											Decimal prevQty = mAccToCount.get(
													accId + ':' + o.ADC_Channel__c + ':' + prodDesc
												) != null
												? mAccToCount.get(accId + ':' + o.ADC_Channel__c + ':' + prodDesc)
												: 0.0;
											System.debug(
												'** Qty of ' +
													accId +
													':' +
													o.ADC_Channel__c +
													':' +
													prodDesc +
													' orders: ' +
													prevQty
											);
											totalQuantity += prevQty;
											accTotalQnty += prevQty;
											System.debug('** updated totalQuantity: ' + totalQuantity);
										}
									}

									if (prodGroup != 'ALL') {
										System.debug(
											'*** containsKey: ' +
												mProductGrpCount.containsKey(prodGroup) +
												' totaQty: ' +
												totalQuantity +
												' yearLimit: ' +
												yearLimit
										);
										if (mProductGrpCount.containsKey(prodGroup)) {
											if (totalQuantity > yearLimit) {
												if (ordSettings.Send_to_pending__c == true) {
													System.debug('** Set to Pending');
													o.ADC_Status__c = 'Pending';
													o.Pending_Message__c = String.format(
														Label.VPRO_DataCableYearLImitMsg,
														new List<String>{ '' + accTotalQnty, '' + qnty, '' + yearLimit }
													);
												} else {
													System.debug('** show error msg');
													o.addError(
														String.format(
															Label.VPRO_DataCableYearLImitMsg,
															new List<String>{
																'' + accTotalQnty,
																'' + qnty,
																'' + yearLimit
															}
														)
													);
													invalidOrders.put(
														o,
														new StatusWrapper(
															false,
															String.format(
																Label.VPRO_DataCableYearLImitMsg,
																new List<String>{
																	'' + accTotalQnty,
																	'' + qnty,
																	'' + yearLimit
																}
															)
														)
													);
												}
											}
										}
									} else if (prodGroup == 'ALL') {
										if (totalQuantity > yearLimit) {
											if (ordSettings.Send_to_pending__c == true) {
												o.ADC_Status__c = 'Pending';
												o.Pending_Message__c = String.format(
													Label.VPRO_DataCableYearLImitMsg,
													new List<String>{ '' + accTotalQnty, '' + qnty, '' + yearLimit }
												);
											} else {
												o.addError(
													String.format(
														Label.VPRO_DataCableYearLImitMsg,
														new List<String>{ '' + accTotalQnty, '' + yearLimit }
													)
												);
												invalidOrders.put(
													o,
													new StatusWrapper(
														false,
														String.format(
															Label.VPRO_DataCableYearLImitMsg,
															new List<String>{
																'' + accTotalQnty,
																'' + qnty,
																'' + yearLimit
															}
														)
													)
												);
											}
										}
									}
								}

								if (latestOrder != null && ordSettings.Num_of_Months_Since_Last_Order__c != null) {
									System.debug('** latestOrder: ' + latestOrder);
									System.debug('** monthsBetween: ' + latestOrder.monthsBetween(Date.today()));

									// SC. 06/11/2020. Bug fix in finding monthsBetween.
									Integer monthsBetween = latestOrder.monthsBetween(Date.today());

									if (prodGroup != 'ALL') {
										if (mProductGrpCount.containsKey(prodGroup)) {
											// SC. 06/11/2020. If the number of months since the last order was less than the number of months.
											// specified in Compliance Order Settings, set the status to Pending and set a Pending Message.
											if (monthsBetween < ordSettings.Num_of_Months_Since_Last_Order__c) {
												if (ordSettings.Send_to_pending__c == true) {
													o.ADC_Status__c = 'Pending';
													o.Pending_Message__c = String.format(
														Label.VPRO_DataCableLastOrderMsg,
														new List<String>{
															'' + ordSettings.Num_of_Months_Since_Last_Order__c,
															'' + latestOrder.format()
														}
													);
												} else {
													o.addError(
														String.format(
															Label.VPRO_DataCableLastOrderMsg,
															new List<String>{
																'' + ordSettings.Num_of_Months_Since_Last_Order__c,
																'' + latestOrder.format()
															}
														)
													);
													invalidOrders.put(
														o,
														new StatusWrapper(
															false,
															String.format(
																Label.VPRO_DataCableLastOrderMsg,
																new List<String>{
																	'' + ordSettings.Num_of_Months_Since_Last_Order__c,
																	'' + latestOrder.format()
																}
															)
														)
													);
												}
											}
										}
									} else {
										// SC. 06/11/2020. If the number of months since the last order was less than the number of months.
										// specified in Compliance Order Settings, set the status to Pending and set a Pending Message.
										if (monthsBetween < ordSettings.Num_of_Months_Since_Last_Order__c) {
											if (ordSettings.Send_to_pending__c == true) {
												o.ADC_Status__c = 'Pending';
												o.Pending_Message__c = String.format(
													Label.VPRO_DataCableLastOrderMsg,
													new List<String>{
														'' + ordSettings.Num_of_Months_Since_Last_Order__c,
														'' + latestOrder.format()
													}
												);
											} else {
												o.addError(
													String.format(
														Label.VPRO_DataCableLastOrderMsg,
														new List<String>{
															'' + ordSettings.Num_of_Months_Since_Last_Order__c,
															'' + latestOrder.format()
														}
													)
												);
												invalidOrders.put(
													o,
													new StatusWrapper(
														false,
														String.format(
															Label.VPRO_DataCableLastOrderMsg,
															new List<String>{
																'' + ordSettings.Num_of_Months_Since_Last_Order__c,
																'' + latestOrder.format()
															}
														)
													)
												);
											}
										}
									}
								}
							}
						}
					}
				}
			}
		}

		return invalidOrders;
	}

	private static void validateEvaluationRequest(
		List<ADC_Compliance_Order__c> lOrderList,
		Map<String, List<ADC_Order_Product__c>> mOrderToOrderProduct,
		Map<String, Map<Id, Map<String, Map<String, Decimal>>>> mOrderTypeToAccCount
	) {
		Map<String, Compliance_Order_Setting__mdt> mOrdSettings = mCompOrderSetting.get(EVALUATION_ORDER_TYPE);

		Map<Id, Map<String, Map<String, Decimal>>> mAccToOrderCount = mOrderTypeToAccCount.get(EVALUATION_ORDER_TYPE);
		List<ADC_Compliance_Order__c> validOrders = new List<ADC_Compliance_Order__c>();
		Map<Id, List<ADC_Compliance_Order__c>> mAccToOrder = new Map<Id, List<ADC_Compliance_Order__c>>();
		for (ADC_Compliance_Order__c o : lOrderList) {
			if (validateProductQuantity(o, mOrderToOrderProduct.get(o.Id)).valid) {
				validOrders.add(o);
				List<ADC_Compliance_Order__c> ltmp = new List<ADC_Compliance_Order__c>();
				if (mAccToOrder.containsKey(o.ADC_Account_Name__c)) {
					ltmp = mAccToOrder.get(o.ADC_Account_Name__c);
				}
				ltmp.add(o);
				mAccToOrder.put(o.ADC_Account_Name__c, lTmp);
			}
		}
		Map<ADC_Compliance_Order__c, StatusWrapper> invalidOrders = new Map<ADC_Compliance_Order__c, StatusWrapper>();
		if (lOrderTypeWithAnnualLimit.contains(EVALUATION_ORDER_TYPE)) {
			invalidOrders = validateAnnualLimit(
				EVALUATION_ORDER_TYPE,
				mAccToOrder,
				mAccToOrderCount,
				null,
				false,
				mOrderToOrderProduct
			);
		}
		for (ADC_Compliance_Order__c o : validOrders) {
			if (!invalidOrders.containsKey(o)) {
				Compliance_Order_Setting__mdt ordSettings = (Compliance_Order_Setting__mdt) mOrdSettings.get(
					EVALUATION_ORDER_TYPE + ':' + o.ADC_Channel__c + ':ALL'
				);
				if (ordSettings == null) {
					ordSettings = (Compliance_Order_Setting__mdt) mOrdSettings.get(EVALUATION_ORDER_TYPE + ':ALL:ALL');
				}
				Schema.RecordTypeInfo toUpdateRecInfo = rtMapByName.get(ordSettings.Submit_Record_Type_API__c);
				String submitRecordTypeId = toUpdateRecInfo.recordtypeid;

				o.RecordTypeId = submitRecordTypeId;
				if (o.ADC_Status__c != 'Pending') {
					o.ADC_Status__c = ordSettings.Final_Status__c;
				}
			}
		}
	}

	private static void validateManagementOrderRequest(
		List<ADC_Compliance_Order__c> lOrderList,
		Map<String, List<ADC_Order_Product__c>> mOrderToOrderProduct,
		Map<String, Map<Id, Map<String, Map<String, Decimal>>>> mOrderTypeToAccCount
	) {
		System.debug('validateManagementOrderRequest Start');
		Map<String, Compliance_Order_Setting__mdt> mOrdSettings = mCompOrderSetting.get(MANAGEMENT_ORDER_TYPE);

		Map<Id, Map<String, Map<String, Decimal>>> mAccToOrderCount = mOrderTypeToAccCount.get(MANAGEMENT_ORDER_TYPE);
		List<ADC_Compliance_Order__c> validOrders = new List<ADC_Compliance_Order__c>();
		Map<Id, List<ADC_Compliance_Order__c>> mAccToOrder = new Map<Id, List<ADC_Compliance_Order__c>>();
		for (ADC_Compliance_Order__c o : lOrderList) {
			System.debug('ADC_Compliance_Order__c o' + o);
			if (validateProductQuantity(o, mOrderToOrderProduct.get(o.Id)).valid) {
				System.debug('validateProductQuantity is valid ');
				validOrders.add(o);
				List<ADC_Compliance_Order__c> ltmp = new List<ADC_Compliance_Order__c>();
				if (mAccToOrder.containsKey(o.ADC_Account_Name__c)) {
					ltmp = mAccToOrder.get(o.ADC_Account_Name__c);
				}
				ltmp.add(o);
				mAccToOrder.put(o.ADC_Account_Name__c, lTmp);
			}
		}

		Map<ADC_Compliance_Order__c, StatusWrapper> invalidOrders = new Map<ADC_Compliance_Order__c, StatusWrapper>();
		System.debug('lOrderTypeWithAnnualLimit.contains(MANAGEMENT_ORDER_TYPE) is valid ');
		if (lOrderTypeWithAnnualLimit.contains(MANAGEMENT_ORDER_TYPE)) {
			invalidOrders = validateAnnualLimit(
				MANAGEMENT_ORDER_TYPE,
				mAccToOrder,
				mAccToOrderCount,
				null,
				false,
				mOrderToOrderProduct
			);
		}
		for (ADC_Compliance_Order__c o : validOrders) {
			if (!invalidOrders.containsKey(o)) {
				Compliance_Order_Setting__mdt ordSettings = (Compliance_Order_Setting__mdt) mOrdSettings.get(
					MANAGEMENT_ORDER_TYPE + ':' + o.ADC_Channel__c + ':ALL'
				);
				if (ordSettings == null) {
					ordSettings = (Compliance_Order_Setting__mdt) mOrdSettings.get(MANAGEMENT_ORDER_TYPE + ':ALL:ALL');
				}
				Schema.RecordTypeInfo toUpdateRecInfo = rtMapByName.get(ordSettings.Submit_Record_Type_API__c);
				String submitRecordTypeId = toUpdateRecInfo.recordtypeid;

				o.RecordTypeId = submitRecordTypeId;
				if (o.ADC_Status__c != 'Pending') {
					o.ADC_Status__c = ordSettings.Final_Status__c;
				}
			}
		}
	}

	private static void validateManagementOrderCGMRequest(
		List<ADC_Compliance_Order__c> lOrderList,
		Map<String, List<ADC_Order_Product__c>> mOrderToOrderProduct,
		Map<String, Map<Id, Map<String, Map<String, Decimal>>>> mOrderTypeToAccCount
	) {
		System.debug('** lOrderList: ' + lOrderList);
		System.debug('** mOrderToOrderProduct: ' + mOrderToOrderProduct);
		System.debug('** mOrderTypeToAccCount: ' + mOrderTypeToAccCount);

		Map<String, Compliance_Order_Setting__mdt> mOrdSettings = mCompOrderSetting.get(
			MANAGEMENT_ORDER_CGM_ORDER_TYPE
		);

		Map<Id, Map<String, Map<String, Decimal>>> mAccToOrderCount = mOrderTypeToAccCount.get(
			MANAGEMENT_ORDER_CGM_ORDER_TYPE
		);
		List<ADC_Compliance_Order__c> validOrders = new List<ADC_Compliance_Order__c>();
		Map<Id, List<ADC_Compliance_Order__c>> mAccToOrder = new Map<Id, List<ADC_Compliance_Order__c>>();
		Map<Id, List<ADC_Compliance_Order__c>> mHCPToOrder = new Map<Id, List<ADC_Compliance_Order__c>>();

		for (ADC_Compliance_Order__c o : lOrderList) {
			if (
				validateProductQuantity(o, mOrderToOrderProduct.get(o.Id)).valid &&
				validateSensorsAndReaders(o, mOrderToOrderProduct.get(o.Id))
			) {
				validOrders.add(o);

				List<ADC_Compliance_Order__c> ltmp = new List<ADC_Compliance_Order__c>();
				if (o.ADC_Channel__c == 'HCP' || o.ADC_Channel__c == 'Market Access') {
					if (mHCPToOrder.containsKey(o.ADC_Contact_Name__c)) {
						ltmp = mHCPToOrder.get(o.ADC_Contact_Name__c);
					}
					ltmp.add(o);
					mHCPToOrder.put(o.ADC_Contact_Name__c, lTmp);
				} else {
					if (mAccToOrder.containsKey(o.ADC_Account_Name__c)) {
						ltmp = mAccToOrder.get(o.ADC_Account_Name__c);
					}
					ltmp.add(o);
					mAccToOrder.put(o.ADC_Account_Name__c, lTmp);
				}
			}
		}
		Map<ADC_Compliance_Order__c, StatusWrapper> invalidOrders = new Map<ADC_Compliance_Order__c, StatusWrapper>();

		if (mAccToOrder != null && !mAccToOrder.isEmpty()) {
			List<Account> lacc = [
				SELECT Id, ADC_Annual_Sample_Quantity_Limit__c
				FROM Account
				WHERE id IN :mAccToOrder.keySet()
			];
			System.debug('lacc-->' + lacc);
			Map<Id, Decimal> mAccLimit = new Map<Id, Decimal>();
			for (Account a : lacc) {
				mAccLimit.put(a.Id, a.ADC_Annual_Sample_Quantity_Limit__c);
			}
			if (lOrderTypeWithAnnualLimit.contains(MANAGEMENT_ORDER_CGM_ORDER_TYPE) || !mAccLimit.isEmpty()) {
				invalidOrders = validateAnnualLimit(
					MANAGEMENT_ORDER_CGM_ORDER_TYPE,
					mAccToOrder,
					mAccToOrderCount,
					mAccLimit,
					true,
					mOrderToOrderProduct
				);
			}
		}
		if (mHCPToOrder != null && !mHCPToOrder.isEmpty()) {
			invalidOrders.putAll(
				validateAnnualSampleLimit(mHCPToOrder, mAccToOrderCount, getHCPSampleLimits(mHCPToOrder.keyset()))
			);
		}

		for (ADC_Compliance_Order__c o : validOrders) {
			if (!invalidOrders.containsKey(o)) {
				Compliance_Order_Setting__mdt ordSettings = (Compliance_Order_Setting__mdt) mOrdSettings.get(
					MANAGEMENT_ORDER_CGM_ORDER_TYPE + ':' + o.ADC_Channel__c + ':ALL'
				);
				if (ordSettings == null) {
					ordSettings = (Compliance_Order_Setting__mdt) mOrdSettings.get(
						MANAGEMENT_ORDER_CGM_ORDER_TYPE + ':ALL:ALL'
					);
				}
				if (rtMapByName != null && ordSettings != null) {
					Schema.RecordTypeInfo toUpdateRecInfo = rtMapByName.get(ordSettings.Submit_Record_Type_API__c);
					String submitRecordTypeId = toUpdateRecInfo.recordtypeid;
					o.RecordTypeId = submitRecordTypeId;
					if (o.ADC_Status__c != 'Pending') {
						o.ADC_Status__c = ordSettings.Final_Status__c;
					}
				}
			}
		}
	}

	private static void validateSensignEduItemsRequest(
		List<ADC_Compliance_Order__c> lOrderList,
		Map<String, List<ADC_Order_Product__c>> mOrderToOrderProduct,
		Map<String, Map<Id, Map<String, Map<String, Decimal>>>> mOrderTypeToAccCount
	) {
		System.debug('** validateSensignEduItemsRequest');

		Map<String, Compliance_Order_Setting__mdt> mOrdSettings = mCompOrderSetting.get(
			SENSING_EDUCATION_ITEMS_ORDER_TYPE
		);

		Map<Id, Map<String, Map<String, Decimal>>> mAccToOrderCount = mOrderTypeToAccCount.get(
			SENSING_EDUCATION_ITEMS_ORDER_TYPE
		);
		List<ADC_Compliance_Order__c> validOrders = new List<ADC_Compliance_Order__c>();
		Map<Id, List<ADC_Compliance_Order__c>> mAccToOrder = new Map<Id, List<ADC_Compliance_Order__c>>();
		for (ADC_Compliance_Order__c o : lOrderList) {
			if (validateProductQuantity(o, mOrderToOrderProduct.get(o.Id)).valid) {
				validOrders.add(o);
				List<ADC_Compliance_Order__c> ltmp = new List<ADC_Compliance_Order__c>();
				if (mAccToOrder.containsKey(o.ADC_Contact_Name__c)) {
					ltmp = mAccToOrder.get(o.ADC_Contact_Name__c);
				}
				ltmp.add(o);
				mAccToOrder.put(o.ADC_Contact_Name__c, lTmp);
			}
		}
		Map<ADC_Compliance_Order__c, StatusWrapper> invalidOrders = new Map<ADC_Compliance_Order__c, StatusWrapper>();

		if (lOrderTypeWithAnnualLimit.contains(SENSING_EDUCATION_ITEMS_ORDER_TYPE)) {
			invalidOrders = validateAnnualLimit(
				SENSING_EDUCATION_ITEMS_ORDER_TYPE,
				mAccToOrder,
				mAccToOrderCount,
				null,
				false,
				mOrderToOrderProduct
			);
		}

		System.debug('** validOrders: ' + validOrders);
		System.debug('** invalidOrders: ' + invalidOrders);

		for (ADC_Compliance_Order__c o : validOrders) {
			if (!invalidOrders.containsKey(o)) {
				Compliance_Order_Setting__mdt ordSettings = (Compliance_Order_Setting__mdt) mOrdSettings.get(
					SENSING_EDUCATION_ITEMS_ORDER_TYPE + ':' + o.ADC_Channel__c + ':ALL'
				);
				if (ordSettings == null) {
					ordSettings = (Compliance_Order_Setting__mdt) mOrdSettings.get(
						SENSING_EDUCATION_ITEMS_ORDER_TYPE + ':ALL:ALL'
					);
				}
				Schema.RecordTypeInfo toUpdateRecInfo = rtMapByName.get(ordSettings.Submit_Record_Type_API__c);
				String submitRecordTypeId = toUpdateRecInfo.recordtypeid;
				o.RecordTypeId = submitRecordTypeId;
				if (o.ADC_Status__c != 'Pending') {
					o.ADC_Status__c = ordSettings.Final_Status__c;
				}
			}
		}
	}

	private static void validateContractedCustomerRequest(
		List<ADC_Compliance_Order__c> lOrderList,
		Map<String, List<ADC_Order_Product__c>> mOrderToOrderProduct,
		Map<String, Map<Id, Map<String, Map<String, Decimal>>>> mOrderTypeToAccCount
	) {
		System.debug('** lOrderList: ' + lOrderList);
		System.debug('** mOrderToOrderProduct: ' + mOrderToOrderProduct);
		System.debug('** mOrderTypeToAccCount: ' + mOrderTypeToAccCount);

		Map<String, Compliance_Order_Setting__mdt> mOrdSettings = mCompOrderSetting.get(CONTRACTED_CUSTOMER_ORDER_TYPE);

		Map<Id, Map<String, Map<String, Decimal>>> mAccToOrderCount = mOrderTypeToAccCount.get(
			CONTRACTED_CUSTOMER_ORDER_TYPE
		);
		List<ADC_Compliance_Order__c> validOrders = new List<ADC_Compliance_Order__c>();
		Map<Id, List<ADC_Compliance_Order__c>> mAccToOrder = new Map<Id, List<ADC_Compliance_Order__c>>();

		for (ADC_Compliance_Order__c o : lOrderList) {
			if (validateProductQuantity(o, mOrderToOrderProduct.get(o.Id)).valid) {
				validOrders.add(o);

				List<ADC_Compliance_Order__c> ltmp = new List<ADC_Compliance_Order__c>();

				if (mAccToOrder.containsKey(o.ADC_Account_Name__c)) {
					ltmp = mAccToOrder.get(o.ADC_Account_Name__c);
				}
				ltmp.add(o);
				mAccToOrder.put(o.ADC_Account_Name__c, lTmp);
			}
		}
		Map<ADC_Compliance_Order__c, StatusWrapper> invalidOrders = new Map<ADC_Compliance_Order__c, StatusWrapper>();

		if (mAccToOrder != null && !mAccToOrder.isEmpty()) {
			invalidOrders.putAll(
				validateContractLimit(mAccToOrder, mAccToOrderCount, getContract(mAccToOrder.keyset()))
			);
		}

		for (ADC_Compliance_Order__c o : validOrders) {
			if (!invalidOrders.containsKey(o)) {
				Compliance_Order_Setting__mdt ordSettings = (Compliance_Order_Setting__mdt) mOrdSettings.get(
					MANAGEMENT_ORDER_CGM_ORDER_TYPE + ':' + o.ADC_Channel__c + ':ALL'
				);
				if (ordSettings == null) {
					ordSettings = (Compliance_Order_Setting__mdt) mOrdSettings.get(
						CONTRACTED_CUSTOMER_ORDER_TYPE + ':ALL:ALL'
					);
				}
				Schema.RecordTypeInfo toUpdateRecInfo = rtMapByName.get(ordSettings.Submit_Record_Type_API__c);
				String submitRecordTypeId = toUpdateRecInfo.recordtypeid;
				o.RecordTypeId = submitRecordTypeId;
				if (o.ADC_Status__c != 'Pending') {
					o.ADC_Status__c = ordSettings.Final_Status__c;
				}
			}
		}
	}

	private static boolean bypassValidationForComplianceTeam(Compliance_Order_Setting__mdt ordSettings) {
		if (ordSettings.By_Pass_Validation_By_Compliance_Team__c) {
			if (isComplianceTeamMember()) {
				return true;
			} else {
				return false;
			}
		} else {
			return false;
		}
	}

	private static boolean isComplianceTeamMember() {
		if (isComplianceTeamMember == null) {
			List<GroupMember> lstgroupmember = [
				SELECT UserOrGroupId, Group.Type, GroupId, group.name
				FROM GroupMember g
				WHERE UserOrGroupId = :userinfo.getUserId() AND group.name = 'Compliance Team'
				LIMIT 1
			];
			if (lstgroupmember.size() > 0) {
				isComplianceTeamMember = true;
			} else {
				isComplianceTeamMember = false;
			}
		}
		return isComplianceTeamMember;
	}

	public static statusWrapper validateProductQuantity(
		ADC_Compliance_Order__c o,
		List<ADC_Order_Product__c> lOrderProduct
	) {
		System.debug('** validateProductQuantity..');
		System.debug('** lOrderProduct: ' + lOrderProduct);

		Map<String, Integer> mProductGroupToCount = new Map<String, Integer>();
		Map<String, Integer> mProductToCount = new Map<String, Integer>();
		Map<String, String> gsgSensorMap = new Map<String, String>();
		Map<String, String> produtNameMap = new Map<String, String>();

		if (lOrderProduct == null || lOrderProduct.isEmpty()) {
			o.addError(String.format(Label.VPRO_InvalidProduct, new List<String>{ '' }));
			return new statusWrapper(false, String.format(Label.VPRO_InvalidProduct, new List<String>{ '' }));
		}

		Decimal totalQuantity = 0;
		SObject sObjacc = null;

		String productCodeofCurrrentCO = null;
		Set<String> productCodeofCurrrentCOSet = new Set<String>();
		String gsgProductExternalId = null;
		Integer gsgProductCount = 0;
		for (ADC_Order_Product__c op : lOrderProduct) {
			System.debug('op.ADC_Product__r.External_ID_vod__c-->' + op.ADC_Product__r.External_ID_vod__c);
			System.debug('op.ADC_Product__r.Product_Type_vod__c-->' + op.ADC_Product__r.Product_Type_vod__c);

			if (!produtNameMap.containsKey(op.ADC_Product__r.External_ID_vod__c)) {
				produtNameMap.put(op.ADC_Product__r.External_ID_vod__c, op.ADC_Product__r.Name);
			}

			if (op.ADC_Product__r.Product_Type_vod__c == 'Sample') {
				productCodeofCurrrentCO = op.ADC_Product__r.External_ID_vod__c;
				productCodeofCurrrentCOSet.add(op.ADC_Product__r.External_ID_vod__c);
			}

			if (op.ADC_Product__c == null) {
				o.addError(String.format(Label.VPRO_InvalidProduct, new List<String>{ op.name }));
				return new statusWrapper(false, String.format(Label.VPRO_InvalidProduct, new List<String>{ op.name }));
			} else if (op.ADC_Quantity__c == null || op.ADC_Quantity__c < 0) {
				o.addError(String.format(Label.VPRO_InvalidOrderQuantity, new List<String>{ op.name }));
				return new statusWrapper(
					false,
					String.format(Label.VPRO_InvalidOrderQuantity, new List<String>{ op.name })
				);
			} else {
				Integer prodCount = 0;

				//KK - GSG
				if (mProductToCount.containsKey(op.ADC_Product__r.External_ID_vod__c)) {
					prodCount = mProductToCount.get(op.ADC_Product__r.External_ID_vod__c);
				}
				Integer totalProdCount = prodCount + op.ADC_Quantity__c.intValue();
				if (totalProdCount == 0) {
					o.addError(Label.VPRO_ProductQtyZero);
					return new statusWrapper(false, Label.VPRO_ProductQtyZero);
				}

				if (op.ADC_Product__r.Sensor_External_Id__c != null && o.ADC_Channel__c == 'POC') {
					if (!gsgSensorMap.containsKey(op.ADC_Product__r.External_ID_vod__c)) {
						gsgSensorMap.put(op.ADC_Product__r.External_ID_vod__c, op.ADC_Product__r.Sensor_External_Id__c);
					}
				}
				//KK - GSG

				System.debug('gsgSensorMap::' + gsgSensorMap);

				System.debug(
					'totalProdCount::' +
						totalProdCount +
						'::prodCount::' +
						prodCount +
						'::op.ADC_Quantity__c.intValue()::' +
						op.ADC_Quantity__c.intValue()
				);

				mProductToCount.put(op.ADC_Product__r.External_ID_vod__c, totalProdCount);

				sObjacc = (SObject) op.getSobject('ADC_Order__r').getSobject('ADC_Account_Name__r');

				Integer val = 0;
				if (mProductGroupToCount.containsKey(op.ADC_Product__r.ADC_Product_Group_Desc__c)) {
					val = mProductGroupToCount.get(op.ADC_Product__r.ADC_Product_Group_Desc__c);
				}
				Integer totalVal = val + op.ADC_Quantity__c.intValue();
				mProductGroupToCount.put(op.ADC_Product__r.ADC_Product_Group_Desc__c, totalVal);
				totalQuantity = totalQuantity + op.ADC_Quantity__c;
			}
		}

		Map<String, String> sampleGSGMap = new Map<String, String>();
		//KK - GSG
		for (String gsgSensor : gsgSensorMap.keySet()) {
			String sensorExternalID = gsgSensorMap.get(gsgSensor);
			System.debug('sensorExternalID::' + sensorExternalID);

			System.debug('mProductToCount::' + mProductToCount);

			if (sensorExternalID != null) {
				if (!sampleGSGMap.containsKey(gsgSensorMap.get(gsgSensor))) {
					sampleGSGMap.put(gsgSensorMap.get(gsgSensor), gsgSensor);
				}

				Decimal sensorC = ((Decimal) mProductToCount.get(sensorExternalID));
				if (sensorC != null) {
					Integer sensorCount = sensorC.intValue();
					Integer calcGsgCount = 0;

					Boolean isEven = Math.mod(sensorCount, 2) == 0;
					if (isEven) {
						calcGsgCount = sensorCount / 2;
					} else {
						calcGsgCount = (sensorCount + 1) / 2; // Makes it a whole number
					}

					Decimal sensorGsg = ((Decimal) mProductToCount.get(gsgSensor));
					gsgProductCount = sensorGsg.intValue();

					System.debug(
						'sensorCount-->' +
							sensorCount +
							'::calcGsgCount::--->' +
							calcGsgCount +
							'::gsgProductCount::--->' +
							gsgProductCount
					);
					String gsgproductName = produtNameMap.get(gsgSensor);
					String sensorProductName = produtNameMap.get(sensorExternalID);

					if (gsgProductCount > calcGsgCount) {
						o.addError(
							gsgproductName +
								' Quantity can be upto ' +
								calcGsgCount +
								' as ' +
								sensorProductName +
								' Quantity is ' +
								sensorCount
						);
						return new statusWrapper(false, 'GSG Product should be the value:' + calcGsgCount);
					}
					if (gsgProductCount == 0 || calcGsgCount == 0) {
						o.addError(
							gsgproductName +
								' Quantity should be greater than Zero and can be up to  ' +
								calcGsgCount +
								' as ' +
								sensorProductName +
								' Quantity is ' +
								sensorCount
						);
						return new statusWrapper(false, 'GSG Product should be the value:' + calcGsgCount);
					}
				} else {
					continue;
				}
			}
		}

		System.debug('sampleGSGMap::' + sampleGSGMap);
		System.debug('productCodeofCurrrentCO::' + productCodeofCurrrentCO);

		Boolean containsAll = productCodeofCurrrentCOSet.containsAll(sampleGSGMap.KeySet());

		Boolean contains = sampleGSGMap.containsKey(productCodeofCurrrentCO);
		if (!containsAll) {
			o.addError(' Please select the appropriate GSG for the Sensor');
			return new statusWrapper(false, 'Please select the appropriate GSG for the Sensor');
		}

		System.debug('** totalQuantity: ' + totalQuantity);
		System.debug('** mProductGroupToCount: ' + mProductGroupToCount);

		String orderType = o.ADC_Order_Type__c;
		map<String, Compliance_Order_Setting__mdt> lOrderSettings = mCompOrderSetting.get(orderType);
		List<Compliance_Order_Setting__mdt> lOrderSettingWithProduct = new List<Compliance_Order_Setting__mdt>();
		if (!lOrderSettings.isEmpty()) {
			for (string key : lOrderSettings.keySet()) {
				System.debug('key-->' + key);
				String[] str = key.split(':');
				String ordType = str[0];
				String channel = str[1];
				String prodGroup = str[2];
				// AZ 3-8-24
				//String prod = str[3];
				Compliance_Order_Setting__mdt ordSettings = lOrderSettings.get(key);
				System.debug('ordSettings.Non_Physical__c-->' + ordSettings.Non_Physical__c);
				System.debug('isNonPhysical-->' + isNonPhysical(o, lOrderProduct));
				System.debug('prodGroup-->' + prodGroup);
				System.debug('mProductGroupToCount-->' + mProductGroupToCount);

				System.debug('ordSettings.product_code__c-->' + ordSettings.product_code__c);
				if (ordSettings.product_code__c != null) {
					lOrderSettingWithProduct.add(ordSettings);
					continue;
				}

				if (
					(ordSettings.Non_Physical__c == true && isNonPhysical(o, lOrderProduct) ||
					ordSettings.Non_Physical__c == false) && !bypassValidationForComplianceTeam(ordSettings)
				) {
					Decimal orderLimit = null;
					System.debug('here-->' + ordSettings.OverrideAccountLevel__c);
					if (
						ordSettings.OverrideAccountLevel__c &&
						ordSettings.Per_Order_Limit_Account_Field_API_Name__c != null
					) {
						if (
							sObjacc != null &&
							sObjacc.get(ordSettings.Per_Order_Limit_Account_Field_API_Name__c) != null
						) {
							orderLimit = (Decimal) sObjacc.get(ordSettings.Per_Order_Limit_Account_Field_API_Name__c);
						} else {
							orderLimit = ordSettings.Per_Order_Limit__c;
						}
					} else if (ordSettings.Per_Order_Limit__c != null) {
						orderLimit = ordSettings.Per_Order_Limit__c;
					}
					System.debug('orderLimit-->' + orderLimit);
					if (orderLimit != null) {
						if (o.ADC_Channel__c == channel || channel == 'ALL') {
							if (prodGroup != 'ALL') {
								System.debug('prodGroup-->' + prodGroup);
								System.debug('ordSettings.has_GSG__c-->' + ordSettings.has_GSG__c);
								System.debug('ordSettings.Label-->' + ordSettings.Label);

								System.debug(
									'mProductGroupToCount.containsKey(prodGroup)-->' +
									mProductGroupToCount.containsKey(prodGroup)
								);
								if (mProductGroupToCount.containsKey(prodGroup)) {
									System.debug('1-->' + (Decimal) mProductGroupToCount.get(prodGroup));
									System.debug('1.1-->' + orderLimit);
									System.debug('2-->' + (Decimal) mProductGroupToCount.get(prodGroup));
									System.debug('3-->' + ordSettings.has_GSG__c);

									if ((Decimal) mProductGroupToCount.get(prodGroup) > orderLimit) {
										if (ordSettings.Send_to_pending__c == true) {
											o.ADC_Status__c = 'Pending';
											o.Pending_Message__c = String.format(
												Label.VPRO_ProductQuantityLimitMsg,
												new List<String>{ '' + orderLimit }
											);
										} else {
											o.addError(
												String.format(
													Label.VPRO_ProductQuantityLimitMsg,
													new List<String>{ '' + orderLimit }
												)
											);

											return new statusWrapper(
												false,
												String.format(
													Label.VPRO_ProductQuantityLimitMsg,
													new List<String>{ '' + orderLimit }
												)
											);
										}
									} else if ((Decimal) mProductGroupToCount.get(prodGroup) == 0) {
										o.addError(Label.VPRO_ProductQtyZero);
										return new statusWrapper(false, Label.VPRO_ProductQtyZero);
									}
								}
							} else if (prodGroup == 'ALL') {
								if (totalQuantity > orderLimit) {
									if (ordSettings.Send_to_pending__c == true) {
										o.ADC_Status__c = 'Pending';
										o.Pending_Message__c = String.format(
											Label.VPRO_ProductQuantityLimitMsg,
											new List<String>{ '' + orderLimit }
										);
									} else {
										o.addError(
											String.format(
												Label.VPRO_ProductQuantityLimitMsg,
												new List<String>{ '' + orderLimit }
											)
										);
										return new statusWrapper(
											false,
											String.format(
												Label.VPRO_ProductQuantityLimitMsg,
												new List<String>{ '' + orderLimit }
											)
										);
									}
								}
								if (totalQuantity == 0) {
									o.addError(Label.VPRO_ProductQtyZero);
									return new statusWrapper(false, Label.VPRO_ProductQtyZero);
								}
							}
						}
					}
				}
			}
			System.debug('lOrderSettingWithProduct.size-->' + lOrderSettingWithProduct.size());
			Integer currentCountOnOrder = 0;
			Compliance_Order_Setting__mdt customSettingmdt = null;

			System.debug('lOrderSettingWithProduct::' + lOrderSettingWithProduct);

			//AZ 3-7-24
			if (lOrderSettingWithProduct != null && !lOrderSettingWithProduct.isEmpty()) {
				for (Compliance_Order_Setting__mdt productOrderSetting : lOrderSettingWithProduct) {
					if (mProductToCount.get(productOrderSetting.product_code__c) != null) {
						if (
							mProductToCount.get(productOrderSetting.product_code__c) >
							productOrderSetting.Per_Order_Limit__c
						) {
							if (productOrderSetting.Send_to_pending__c == true) {
								System.debug('Go to pending-->');
								o.ADC_Status__c = 'Pending';
								o.Pending_Message__c = String.format(
									Label.VPRO_ProductQuantityLimitMsg,
									new List<String>{ '' + productOrderSetting.Per_Order_Limit__c }
								);
							} else {
								System.debug('show error-->');
								o.addError(
									String.format(
										Label.VPRO_ProductQuantityLimitMsg,
										new List<String>{ '' + productOrderSetting.Per_Order_Limit__c }
									)
								);
								return new statusWrapper(
									false,
									String.format(
										Label.VPRO_ProductQuantityLimitMsg,
										new List<String>{ '' + productOrderSetting.Per_Order_Limit__c }
									)
								);
							}
						} else if (mProductToCount.get(productOrderSetting.product_code__c) == 0) {
							o.addError(Label.VPRO_ProductQtyZero);
							return new statusWrapper(false, Label.VPRO_ProductQtyZero);
						}
					}
				}
			}

			for (Compliance_Order_Setting__mdt productOrderSetting : lOrderSettingWithProduct) {
				System.debug(
					'productCodeofCurrrentCO::' +
						productCodeofCurrrentCO +
						'::productOrderSetting.product_code__c::' +
						productOrderSetting.product_code__c
				);

				if (productCodeofCurrrentCO != null && productCodeofCurrrentCO == productOrderSetting.product_code__c) {
					currentCountOnOrder = mProductToCount.get(productOrderSetting.product_code__c);
					System.debug('currentCountOnOrder::' + currentCountOnOrder);
					customSettingmdt = productOrderSetting;
					System.debug('customSettingmdt::' + customSettingmdt);
				}
			}

			System.debug('customSettingmdt::' + customSettingmdt);

			if (customSettingmdt != null) {
				System.debug('currentCountOnOrder-->' + currentCountOnOrder);
				System.debug('productOrderSetting.Per_Order_Limit__c-->' + customSettingmdt.Per_Order_Limit__c);
				if (currentCountOnOrder > customSettingmdt.Per_Order_Limit__c) {
					if (customSettingmdt.Send_to_pending__c == true) {
						System.debug('Go to pending-->');
						o.ADC_Status__c = 'Pending';
						o.Pending_Message__c = String.format(
							Label.VPRO_ProductQuantityLimitMsg,
							new List<String>{ '' + customSettingmdt.Per_Order_Limit__c }
						);
					} else {
						System.debug('show error-->');
						o.addError(
							String.format(
								Label.VPRO_ProductQuantityLimitMsg,
								new List<String>{ '' + customSettingmdt.Per_Order_Limit__c }
							)
						);
						return new statusWrapper(
							false,
							String.format(
								Label.VPRO_ProductQuantityLimitMsg,
								new List<String>{ '' + customSettingmdt.Per_Order_Limit__c }
							)
						);
					}
				} else if (currentCountOnOrder == 0) {
					o.addError(Label.VPRO_ProductQtyZero);
					return new statusWrapper(false, Label.VPRO_ProductQtyZero);
				}
			}
		}

		return new statusWrapper(true, null);
	}

	public static boolean isNonPhysical(ADC_Compliance_Order__c o, List<ADC_Order_Product__c> lOrderProduct) {
		Decimal numOfSensors = 0;
		Decimal numOfHDPPocket = 0;
		if (o.ADC_Order_Type__c == MANAGEMENT_ORDER_CGM_ORDER_TYPE) {
			for (ADC_Order_Product__c op : lOrderProduct) {
				if (op.ADC_Product__r.ADC_Product_Group_Desc__c == 'Sensors') {
					numOfSensors = numOfSensors + op.ADC_Quantity__c;
				} else if (op.ADC_Product__r.ADC_Product_Group_Desc__c == 'HDP Packet') {
					numOfHDPPocket = numOfHDPPocket + op.ADC_Quantity__c;
				}
			}
			if (numOfSensors > 0 && numOfHDPPocket > 0) {
				return false;
			} else if (numOfHDPPocket > 0) {
				return true;
			} else {
				return false;
			}
		}
		return false;
	}

	public static boolean validateProductRatios(
		ADC_Compliance_Order__c o,
		List<ADC_Order_Product__c> lOrderProduct,
		String currUserProfileName
	) {
		String query =
			' SELECT recordType.developername,Channel__c,Compliance_Order_Type__c,Profile__c,Product_1__c, Product_2__c, Product_1__r.External_ID_vod__c, Product_2__r.External_ID_vod__c,Product_Group_1__c, Product_Group_2__c, Ratio__c ,Verify_for_added_Product_only__c' +
			' FROM ADC_Compliance_Order_Product_Config__c ' +
			' WHERE ' +
			+' Compliance_Order_Type__c = \'' +
			o.ADC_Order_Type__c +
			'\'' +
			' AND Channel__c includes (\'' +
			o.ADC_channel__c +
			'\')' +
			' AND Profile__c includes (\'' +
			currUserProfileName +
			'\')' +
			' AND (recordType.developername = \'CO_Ratio_By_Product_Group\' OR recordType.developername = \'CO_Ratio_by_Product\')';

		System.debug('ratio query-->' + query);
		List<ADC_Compliance_Order_Product_Config__c> lcoProdConfig = Database.query(query);
		Map<String, String> productToName = new Map<String, String>();
		Map<String, Decimal> mProductToQnty = new Map<String, Decimal>();
		Map<String, Decimal> mGroupToQnty = new Map<String, Decimal>();
		Map<String, String> mRatio = new Map<String, String>();
		Set<String> lverifyOnlyForAdded = new Set<String>();
		if (lcoProdConfig != null && lcoProdConfig.size() > 0) {
			for (ADC_Compliance_Order_Product_Config__c copc : lcoProdConfig) {
				if (copc.recordType.developername == 'CO_Ratio_By_Product_Group') {
					mGroupToQnty.put(copc.Product_Group_1__c, 0);
					mGroupToQnty.put(copc.Product_Group_2__c, 0);
					mRatio.put('GROUP:' + copc.Product_Group_1__c + ':' + copc.Product_Group_2__c, copc.Ratio__c);
					if (copc.Verify_for_added_Product_only__c) {
						lverifyOnlyForAdded.add('GROUP:' + copc.Product_Group_1__c + ':' + copc.Product_Group_2__c);
					}
				} else if (copc.recordType.developername == 'CO_Ratio_by_Product') {
					mProductToQnty.put(copc.Product_1__r.External_ID_vod__c, 0);
					mProductToQnty.put(copc.Product_2__r.External_ID_vod__c, 0);
					mRatio.put(
						'PRODUCT:' + copc.Product_1__r.External_ID_vod__c + ':' + copc.Product_2__r.External_ID_vod__c,
						copc.Ratio__c
					);
					if (copc.Verify_for_added_Product_only__c) {
						lverifyOnlyForAdded.add(
							'PRODUCT:' +
								copc.Product_1__r.External_ID_vod__c +
								':' +
								copc.Product_2__r.External_ID_vod__c
						);
					}
				}
			}
		}
		for (ADC_Order_Product__c op : lOrderProduct) {
			if (mProductToQnty.containsKey(op.ADC_Product__r.External_ID_vod__c)) {
				mProductToQnty.put(
					op.ADC_Product__r.External_ID_vod__c,
					((Decimal) mProductToQnty.get(op.ADC_Product__r.External_ID_vod__c)) + op.ADC_Quantity__c
				);
			}
			if (mGroupToQnty.containsKey(op.ADC_Product__r.ADC_Product_Group_Desc__c)) {
				mGroupToQnty.put(
					op.ADC_Product__r.ADC_Product_Group_Desc__c,
					((Decimal) mGroupToQnty.get(op.ADC_Product__r.ADC_Product_Group_Desc__c)) + op.ADC_Quantity__c
				);
			}
		}
		System.debug('mRatio-->' + mRatio);
		System.debug('mProductToQnty-->' + mProductToQnty);
		System.debug('mGroupToQnty-->' + mGroupToQnty);
		for (String key : mRatio.keySet()) {
			String strRatio = mRatio.get(key);
			String[] lratio = strRatio.split(':');

			Decimal ratio1 = Decimal.valueOf(lratio[0]);
			Decimal ratio2 = Decimal.valueOf(lratio[1]);
			String[] str = key.split(':');
			String type = String.valueOf(str[0]);
			String product1 = str[1];
			String product2 = str[2];
			Decimal qnty1 = 0;
			Decimal qnty2 = 0;

			if (type == 'GROUP') {
				qnty1 = mGroupToQnty.get(product1);
				qnty2 = mGroupToQnty.get(product2);
			} else {
				qnty1 = mProductToQnty.get(product1);
				qnty2 = mProductToQnty.get(product2);
			}
			System.debug('qnty1-->' + qnty1);
			System.debug('qnty2-->' + qnty2);
			//Ignore if the flag is set to verify ratio only if the product is added
			if ((qnty1 == 0 || qnty2 == 0) && lverifyOnlyForAdded.contains(key)) {
				System.debug('Verify On Add is true and quantity is 0 hence skip-->');
				continue;
			}

			Decimal gcd = getGCD(qnty1, qnty2);
			System.debug('GCD->' + gcd);
			System.debug('qnty1/gcd->' + qnty1 / gcd);
			System.debug('qnty2/gcd->' + qnty2 / gcd);
			System.debug('ratio1->' + ratio1);
			System.debug('ratio1->' + ratio2);
			if (qnty1 / gcd != ratio1 || qnty2 / gcd != ratio2) {
				o.addError('Invalid ratio between (' + product1 + ',' + product2 + '). The valid ratio is:' + strRatio);
				return false;
			}
		}
		return true;
	}
	private static Decimal getGCD(Decimal a, Decimal b) {
		Decimal r, i;
		while (b != 0) {
			r = Math.mod(Integer.valueOf(a), Integer.valueOf(b));
			a = b;
			b = r;
		}
		return a;
	}

	public static boolean validateSensorsAndReaders(
		ADC_Compliance_Order__c o,
		List<ADC_Order_Product__c> lOrderProduct
	) {
		System.debug('** validateSensorsAndReaders.');
		Decimal numOfSensors = 0;
		Decimal numOfReaders = 0;
		Decimal orderLimitPerOrder = 0;
		Decimal numOfHDPPocket = 0;

		System.debug('** lOrderProduct:' + lOrderProduct);
		System.debug('** order: ' + o);

		// ---------------------------------------------------
		// SC. 08/17/2020 release.
		//Modified this logic on 08/05/2020 to handle 14Day Sensor along with FSL2 products

		// Currently we have just 14Day Sensors. But adding logic to handle readers, etc. in the future
		Decimal addtlSensors = 0;
		Decimal addtlReaders = 0;
		Decimal addtlHDPPocket = 0;

		System.debug('** ADDTL_GROUP_OF_PRODUCTS: ' + ADDTL_GROUP_OF_PRODUCTS);

		if (ADDTL_GROUP_OF_PRODUCTS.size() > 0) {
			for (ADC_Order_Product__c op : lOrderProduct) {
				orderLimitPerOrder = op.ADC_Order__r.ADC_Account_Name__r.ADC_Sample_Quantity_Limit_Per_Order__c;
				System.debug('** product: ' + op);
				System.debug('** orderLimitPerOrder: ' + orderLimitPerOrder);
				System.debug('** orderLimitPerOrder: ' + orderLimitPerOrder);

				System.debug(
					'** op.ADC_Product__r.ADC_Product_Group_Desc__c: ' + op.ADC_Product__r.ADC_Product_Group_Desc__c
				);

				if (ADDTL_GROUP_OF_PRODUCTS.contains(op.ADC_Product__r.External_ID_vod__c)) {
					if (op.ADC_Product__r.ADC_Product_Group_Desc__c == 'Readers') {
						addtlReaders += op.ADC_Quantity__c;
					} else if (op.ADC_Product__r.ADC_Product_Group_Desc__c == 'Sensors') {
						addtlSensors += op.ADC_Quantity__c;
					} else if (op.ADC_Product__r.ADC_Product_Group_Desc__c == 'HDP Packet') {
						addtlHDPPocket += op.ADC_Quantity__c;
					}
				} else {
					if (op.ADC_Product__r.ADC_Product_Group_Desc__c == 'Sensors') {
						numOfSensors = numOfSensors + op.ADC_Quantity__c;
					} else if (op.ADC_Product__r.ADC_Product_Group_Desc__c == 'Readers') {
						numOfReaders = numOfReaders + op.ADC_Quantity__c;
					} else if (op.ADC_Product__r.ADC_Product_Group_Desc__c == 'HDP Packet') {
						numOfHDPPocket = numOfHDPPocket + op.ADC_Quantity__c;
					}
				}
			}
		} else {
			// SC. Old logic where we handle only one set of products.
			// If there is no 14 Day Sensor, and only FSL2 products, the following logic alone would work fine.
			System.debug('** There are no ADDTL_GROUP_OF_PRODUCTS');

			for (ADC_Order_Product__c op : lOrderProduct) {
				orderLimitPerOrder = op.ADC_Order__r.ADC_Account_Name__r.ADC_Sample_Quantity_Limit_Per_Order__c;
				if (op.ADC_Product__r.ADC_Product_Group_Desc__c == 'Sensors') {
					numOfSensors = numOfSensors + op.ADC_Quantity__c;
				} else if (op.ADC_Product__r.ADC_Product_Group_Desc__c == 'Readers') {
					numOfReaders = numOfReaders + op.ADC_Quantity__c;
				} else if (op.ADC_Product__r.ADC_Product_Group_Desc__c == 'HDP Packet') {
					numOfHDPPocket = numOfHDPPocket + op.ADC_Quantity__c;
				}
			}
		}
		System.debug(
			'** addtlSensors: ' + addtlSensors + ', addtlReaders:' + addtlReaders + ', addtlHDPPocket:' + addtlHDPPocket
		);
		System.debug(
			'** numOfSensors: ' + numOfSensors + ', numOfReaders:' + numOfReaders + ', numOfHDPPocket:' + numOfHDPPocket
		);

		// Ignore addtlReaders and addtlHDPPocket since only 14day Sensors are added now.
		// addtlReaders and addtlHDPPocket are also added just in case there are future requirements.

		// ---- Business Rule: User cannot add 14Day Sensors along with FSL2 products ----
		if (((addtlSensors + addtlReaders) > 0) && ((numOfSensors + numOfReaders) > 0)) {
			o.addError(Label.VPRO_Create_Separate_Order_for_14Day_Sensor);
			return false;
		}

		//---- Check for the required Specialty Flags ----
		Account hcp;
		if (o.ADC_Contact_Name__c != null) {
			// Get Specialty flags on the HCP
			System.debug('** contact: ' + o.ADC_Contact_Name__c);
			List<Account> hcpList = [
				SELECT Id, Name, Specialty_1_vod__c, ADC_Approved_Specialty__c, FSL_Approved_Specialty__c
				FROM Account
				WHERE Id = :o.ADC_Contact_Name__c
			];
			System.debug('** hcpList: ' + hcpList);
			if (hcpList.size() > 0) {
				hcp = hcpList.get(0);
			} else {
				System.debug('** Insufficient Privileges to access HCP');
				o.addError(Label.VPRO_Insufficient_Privileges_HCP);
				return false;
			}
		}
		System.debug('** hcp flags: ' + hcp);

		// New Requirement. 08/12/2020.
		// Logic is different for POC vs. HCP & GOV Channels
		// For POC Channel, CGM Orders, HCP's Specialty value of HOSPITALIST overrides the Approved Specialty Flag.

		if (o.ADC_Channel__c == 'POC') {
			// 14Day Sensor is not added to POC Channels.
			if ((numOfSensors + numOfReaders) > 0) {
				// SC. 04/30/2021. Fixed a bug in the logic.

				Boolean canOrderFSL2 = false;
				// If uppercase value of Specialty of the HCP = ‘HOSPITALIST’ OR
				// uppercase value of Specialty of the HCP = ‘HOSPITALIST (PEDIATRICS)’
				// HCP can order FSL2 products
				if (
					(hcp != null) &&
					(hcp.Specialty_1_vod__c != null) &&
					(POC_HCP_SPECIALTY_OVERRIDE.contains(hcp.Specialty_1_vod__c.toUpperCase()))
				) {
					canOrderFSL2 = true;
					System.debug('** Specialty_1_vod__c: ' + hcp.Specialty_1_vod__c + '. Can order FSL2 products.');
				}
				// If the Specialty of the HCP doesn’t match with above rule, check for the FSL2 Approved Specialty flag.
				// If FSL2 Approved Specialty flag is checked, HCP can order FSL2 products
				else if (hcp.ADC_Approved_Specialty__c == true) {
					canOrderFSL2 = true;
					System.debug('** Approved Specialty flag is checked. Can order FSL2 products');
				}
				// If FSL2 Approved Specialty flag is NOT checked, show an error message
				if (canOrderFSL2 == false) {
					System.debug('** Cannot order FSL2 products');
					o.addError(Label.VPRO_No_Approved_Specialty);
					return false;
				}
			}
		} else {
			// HCP & GOV Channels
			// If both Specialty flags are false, and user is trying to add Readers/Sensors to the order
			if ((numOfSensors + numOfReaders + addtlSensors) > 0) {
				if (
					(hcp != null) &&
					(hcp.ADC_Approved_Specialty__c == false) &&
					(hcp.FSL_Approved_Specialty__c == false)
				) {
					o.addError(Label.VPRO_Approved_Specialty_None);
					return false;
				}
			}

			// User is adding 14Day Sensor to the order, but FSL_Approved_Specialty__c flag set to be false
			if ((addtlSensors) > 0) {
				if ((hcp != null) && (hcp.FSL_Approved_Specialty__c == false)) {
					o.addError(Label.VPRO_No_FSL_Approved_Specialty);
					return false;
				}
			}
		}

		// User is adding FSL2 products to the order, but ADC_Approved_Specialty__c flag set to be false scenario doesn't arise as per requirements

		// End of new code for 08/17/20 release to handle  14Day Sensor along with FSL2 products.
		// ---------------------------------------------------

		// SC. 07/28/2020
		// For FSL2, Sensors cannot be added alone. Readers cannot be added alone.
		// Both would be added in equal measure
		/*if (numOfSensors != numOfReaders) {
            o.addError(Label.VPRO_InvalidSensorsReadersMsg);
            return false;            
        }*/

		/*
        // SC. 07/28/2020. Commented out for FSL2 release
        
        // Only readers cannot be added
        if(numOfSensors == 0 && numOfReaders > 0){
            o.addError(Label.VPRO_CO_Readers_Only_Err_Msg);
            return false;
        }

        // Number of Readers cannot be more than number of sensors
        if(numOfReaders > numOfSensors){
            o.addError(Label.VPRO_Readers_Sensors_qnty_Err_Msg);
            return false;
        }

*/

		/*if(o.ADC_Channel__c != 'POC' && numOfHDPPocket > 0){
            o.addError('HDP Packets can only ordered for POC channel');
            return false;
        }*/

		System.debug('*** orderLimitPerOrder: ' + orderLimitPerOrder);
		System.debug('*** numOfSensors: ' + numOfSensors);
		System.debug('*** numOfReaders: ' + numOfReaders);

		if (orderLimitPerOrder < numOfSensors || orderLimitPerOrder < numOfReaders) {
			o.addError(String.format(Label.VPRO_ProductQuantityLimitMsg, new List<String>{ '' + orderLimitPerOrder }));
			return false;
		}

		return true;
	}

	public class statusWrapper {
		public boolean valid { get; set; }
		public String errMsg { get; set; }
		public statusWrapper() {
		}

		public statusWrapper(boolean valid, String errMsg) {
			this.valid = valid;
			this.errMsg = errMsg;
		}
	}
}