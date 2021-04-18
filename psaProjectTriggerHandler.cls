/**************************************************************************************
  // Name          : psaProjectTriggerHandler
  // Date          : March 1, 2015
  // Description   : Handles all inserts/updates/deletes called by the psaAccountDiscount trigger
  //                 Includes updating Discount Billing Levels on the Project, 
  //                  since a Multi-select picklist field cannot be used in a Formula.
  // Author        : CLD Partners
  // Revisions     : 2015-03-01   Schwartz    Initial version 
  //               : 2015-04-08   Klassen     Added setAccountDiscountBillingLevels method
  //               : 2015-04-27   Klassen     Fix bug with soql query in for loop (pm_contacts)
  //                                          and code refactor for project location creation
  : 2015-05-04   Spano       Changed code logic to stop utilizing Sites and PSA_Location objects. Now uses
  Account BillingAddress fields to set Project Locaiton address fields.
  TBD: Whether to use the Account Contact Record instead
  : 2015-07-08   Mayfield    Modified to remove postal code from project locations
  : 2015-07-10   Mayfield    Modified to pull project locations for all project types,
  commented out several debug statements to reduce log size
  : 2015-07-13   Mayfield    Added if statement to prevent checking change in start date if its null 
  : 2015-07-14   Klassen     Add null check to RR and Assignment Lists when shifting dates if Project start date shifts
  : 2016-12-06   Spano       Add new code to change the PM user on associated billing events when the project manager changes
  : 2018-03-12   Spano       Add new code to check to make sure if the Expenses Billing Rules are Percent or Flat based, there is only one Account Credit
 ***************************************************************************************/
public with sharing class psaProjectTriggerHandler implements psaITriggerHandler {

    Map<Id, Id> pm_resource_sfdcUserMap = new Map<Id, Id> ();
    Map<Id, pse__Proj__c> projectDatesUpdated = new Map<Id, pse__Proj__c> ();
    Map<Id, List<pse__Resource_Request__c>> resReqMap = new Map<Id, List<pse__Resource_Request__c>> ();
    Map<Id, List<pse__Assignment__c>> assignmentMap = new Map<Id, List<pse__Assignment__c>> ();
    Map<Id, pse__Schedule__c> assignmentToSched = new Map<Id, pse__Schedule__c> ();
  
    List<pse__Project_Location__c> projLocations = new List<pse__Project_Location__c> ();
    List<pse__Billing_Event__c> besToUpdate = new List<pse__Billing_Event__c> ();
    List<Id> projToAddLocations = new List<Id> ();
    List<pse__Resource_Request__c> rrtoUpdate = new List<pse__Resource_Request__c> ();
    List<pse__Assignment__c> assignToUpdate = new List<pse__Assignment__c> ();
    List<pse__Project_Location__c> locationsUpdate = new List<pse__Project_Location__c> ();
    List<pse__Schedule__c> schedToUpdate = new List<pse__Schedule__c> ();
    Map<Id, List<PSA_Implementer__c>> impMap = new Map<Id, List<PSA_Implementer__c>> ();
    Map<Id, List<pse__Billing_Event__c>> beMap = new Map<Id, List<pse__Billing_Event__c>> ();
    Map<Id, pse__Proj__c> newProjMap = new Map<Id, pse__Proj__c> ();
    Map<id, List<Assets_Involved__c>> projToAssets = new Map<id, List<Assets_Involved__c>>();
  
    //Spano update 5/4
    Map<Id, Account> accounts = new Map<Id, Account> ();
    Map<Id, List<Account>> childAccounts = new Map<Id, List<Account>> ();
  
    Set<String> addressesAdded = new Set<String> ();
  
    //Hari updated 6/12
    Map<Id, PSA_Rate_Set__c> RateSetMap = new Map<Id, PSA_Rate_Set__c> ();
    Map<id, List<PSA_Rate__c>> RatesMap = new Map<id, List<PSA_Rate__c>> ();
    List<PSA_Rate_Set__c> newRateSetLst = new List<PSA_Rate_Set__c> ();
    List<PSA_Rate__c> newRatesLst = new List<PSA_Rate__c> ();
  
    //hari updated 1/26/2018 : CHG0030554
    Map<Id, List<pse__Resource_Request__c>> resReqCancelMap = new Map<Id, List<pse__Resource_Request__c>> ();
    List<pse__Resource_Request__c> resReqCancelLst = new List<pse__Resource_Request__c> ();
    //Map<Id, PSA_Project_Account_Credit__c> expensePACs = new Map<Id, PSA_Project_Account_Credit__c>();
  
    //hari updated 3/28/2018 : CHG0030532
    Map<Id, List<Assets_Involved__c>> assetsInvolvedMap = new Map<Id, List<Assets_Involved__c>> ();
    List<Assets_Involved__c> assetsInvolvedTarget = new List<Assets_Involved__c> ();
  
    //Hari updated 10/2/2018 :  CHG0031210
    Map<String, Product2> ProductsMap = new Map<String, Product2> ();
    Map<Id,Date> relatedProjectGoLiveDateMap = new Map<Id,Date>();
    Map<Id,Date> goLiveDateUpdateProjectMap = new Map<Id,Date>();
    List<pse__Proj__c> updateProjectGoLive = new List<pse__Proj__c>();
  
    //Hari updated 3/27/2019 : CHG0032297
    /*Set<Id> defaultAssignmentResourceIds = new Set<Id> ();
    List<Contact> defaultAssignmentResources = new List<Contact> ();
    List<pse__Proj__c> defaultAssignmentProjects = new List<pse__Proj__c> ();
    List<pse__Schedule__c> defaultAssignmentSchedules = new List<pse__Schedule__c> ();
    List<pse__Assignment__c> defaultAssignments = new List<pse__Assignment__c> ();*/
  
  
    public psaProjectTriggerHandler() { }
  
    /**************************************************************************************
      // Name        : bulkBefore
      // Description : This method is called prior to execution of a BEFORE trigger. Use 
      //               this to cache any data required into maps prior to execution of the 
      //               trigger.
     ***************************************************************************************/
    public void bulkBefore() {
      /*
        if (psaTriggerMonitor.ExecutedTriggers.contains('psaProjectTriggerHandler')) {
        System.debug('Skipping psaProjectTriggerHandler bulkBefore method due to trigger recursion prevention');
        return;
        }
       */
  
      Set<Id> psaAccountDiscountIds = new Set<Id> ();
      Set<Id> pm_ids = new Set<Id> ();
      Set<Id> projectIds = new Set<Id> ();
      Set<String> productLines = new Set<String> ();
      Set<Id> projForAssets = new Set<Id>();
      Set<Id> relatedProjectIdSet = new Set<Id>();
      pse__Proj__c projold;
      for (SObject so : trigger.new) {
        pse__Proj__c proj = (pse__Proj__c) so;
        projectIds.add(proj.id);
        // Get a cross ref of pm to sfdc user...
        if (proj.pse__Project_Manager__c != null) {
          pm_ids.add(proj.pse__Project_Manager__c);
        } 
      if(trigger.isUpdate){
          projold = (pse__Proj__c) trigger.oldmap.get(proj.id);

          if(projold.PSA_Current_Go_Live_Date__c != proj.PSA_Current_Go_Live_Date__c){
            projForAssets.add(proj.id);
          }
          if((projold.pse__Stage__c != 'In Progress' && proj.pse__Stage__c == 'In Progress') || 
          (projold.pse__Stage__c != 'Completed' && proj.pse__Stage__c == 'Completed') /*|| 
          (projold.pse__Stage__c != 'Closed' && proj.pse__Stage__c == 'Closed')*/){
            proj.Ops_Audit_Required__c = true;
          }
          Boolean hasPermission = FeatureManagement.checkPermission('PSA_Set_Project_Stage_to_Closed');
          if(hasPermission){
            if(((projold.pse__Stage__c != 'Completed' && projold.pse__Stage__c != 'Open - No GW Involved' ) && proj.pse__Stage__c == 'Closed' && projold.pse__Stage__c != 'Closed' && proj.AI_Attached__c == true) ){
            // system.debug('Old Stage value ' + projold.pse__Stage__c   + ' New Stage Value '+ proj.pse__Stage__c);
            proj.pse__Stage__c.addError('Project managers or DMs can set project stage to "Closed" only when stage is either "Completed" or "Open - No GW Involved"');
            } 
          }
        }
        if (proj.PSA_Product_Line__c != null || proj.PSA_Product_Line__c != '') {
          String prjProdName = proj.PSA_Product_Line__c;
          if((proj.PSA_Product_Line__c.contains('Cloud') || proj.PSA_Product_Line__c.contains('InsuranceNow') || proj.PSA_Product_Line__c.contains('Underwriting')) && proj.PSA_Cloud_Tax_Override__c != true ){
            proj.PSA_Cloud_Tax__c = true;
          }else if( !proj.PSA_Product_Line__c.contains('Cloud') && proj.pse__Stage__c == 'Draft' || proj.pse__Stage__c == 'PM Review' || proj.pse__Stage__c == 'Operations Review') {
            proj.PSA_Cloud_Tax__c = false;
          }
          if (String.isNotBlank(prjProdName)) {
            if (prjProdName.containsIgnoreCase(';')) {
              List<String> parts = prjProdName.split(';');
              parts.sort();
              prjProdName = String.join(parts, '-');
              productLines.add(prjProdName);
            }
            else {
              productLines.add(prjProdName);
            }
          }
    }
		if(projold != null && projold.PSA_Cloud_Tax_Override__c != true && proj.PSA_Cloud_Tax_Override__c == true){
			proj.PSA_Cloud_Tax__c = proj.PSA_Cloud_Tax__c;
		}			

      }
      System.debug('*** Product Lines: ' + productLines);
  
      //expensePACs = new Map<Id, PSA_Project_Account_Credit__c>([Select Id from PSA_Project_Account_Credit__c where PSA_Account_Credit__r.Types__c = 'Expenses' AND Project__c in :projectIDs]);
      
      if(projForAssets.size() > 0){
          List<Assets_Involved__c> assets = [Select Id, Project__c from Assets_Involved__c where Project__c in :projForAssets];
          for(Assets_Involved__c asset : assets){
              List<Assets_Involved__c> existing = projToAssets.get(asset.Project__c) != null ? projToAssets.get(asset.Project__c) : new List<Assets_Involved__c>();
              existing.add(asset);
              projToAssets.put(asset.Project__c, existing);
          }
      }

      List<PSA_Implementer__c> implementers = [Select id, psa_Project__c from PSA_Implementer__c where psa_Project__c in :projectIds];
      if (implementers != null && implementers.size() > 0) {
        for (PSA_Implementer__c imp : implementers) {
          List<PSA_Implementer__c> imps = impMap.get(imp.psa_Project__c);
          if (imps == null) {
            imps = new List<PSA_Implementer__c> ();
          }
          imps.add(imp);
          impMap.put(imp.psa_project__c, imps);
        }
      }
  
      //BEGIN Modified by cklassen 4/27/15 - Move soql outside of for loop
      List<Contact> pm_contacts = new List<Contact> ();
      if (pm_ids.size() > 0) {
        pm_contacts =
        [SELECT Id, pse__Salesforce_User__c
        FROM CONTACT
        WHERE Id IN : pm_ids
        ];
      }
      //Populate the resource/user map
      if (pm_contacts != null && pm_contacts.size() > 0) {
        for (Contact pm_contact : pm_contacts) {
          pm_resource_sfdcUserMap.put(pm_contact.Id, pm_contact.pse__Salesforce_User__c);
        }
      }
  
      Set<Id> acctIds = new Set<Id> ();
      for (SObject so : Trigger.new) {
        pse__Proj__c proj = (pse__Proj__c) so;
        if (proj.Pse__Account__c != null) {
          acctIds.add(proj.PSE__Account__c);
        }
        if (proj.PSA_Customer_Account__c != null) {
          acctIds.add(proj.PSA_Customer_Account__c);
        }
      }
  
      if (acctIds.size() > 0) {
        accounts = new Map<Id, Account> ([Select Id, BillingStreet, BillingCity, BillingState, BillingPostalCode, BillingCountry, CS_Account_Short_Name__c
                                         from Account where Id in :acctIds]);
        System.debug('*** The accounts related to the projects: ' + accounts);
      }
  
      //Hari updated 10/2/2018 :  CHG0031210
      if (productLines.size() > 0) {
        List<Product2> products = [Select Id, Name, Product_Number__c, ProductCode From Product2 WHERE Name = :productLines];
        if (products.size() > 0) {
          for (Product2 prod : products) {
            ProductsMap.put(prod.Name, prod);
          }
          System.debug('*** The products related to the projects: ' + ProductsMap);
        }
      }
  
      //END Modified by cklassen 4/27/15 - Move soql outside of for loop
      
      //START SD 03/29 - FFPSA-131
      if(trigger.isInsert) {
        for(SObject so : trigger.new) {
          pse__Proj__c proj = (pse__Proj__c) so;
          if(proj.Related_Project__c != NULL && proj.PSA_Services_Product__c == 'Cloud Assurances') {
            relatedProjectIdSet.add(proj.Related_Project__c);
          }
        }
      } 
      
      if(trigger.isUpdate) {
        for(SObject so : trigger.new) {
          pse__Proj__c proj = (pse__Proj__c) so;
          if(proj.Related_Project__c != NULL && proj.PSA_Services_Product__c == 'Cloud Assurances' && proj.Related_Project__c != projold.Related_Project__c) {
            relatedProjectIdSet.add(proj.Related_Project__c);
          }
          
         
        }
      }
      
      if(relatedProjectIdSet.size()> 0) {
        for(pse__Proj__c relProj: [Select Id,PSA_Current_Go_Live_Date__c
                                        from pse__Proj__c 
                                        where Id in:relatedProjectIdSet]) {
          relatedProjectGoLiveDateMap.put(relProj.Id,relProj.PSA_Current_Go_Live_Date__c);                               
        }
      }
    }
  
    /**************************************************************************************
      // Name        : bulkAfter
      // Description : This method is called prior to execution of a AFTER trigger. Use 
      //               this to cache any data required into maps prior to execution of the 
      //               trigger.
      // Updated 5/4 Spano 
     ***************************************************************************************/
    public void bulkAfter() {
  
  
      //Retrieve accounts related to the project
      if (Trigger.isInsert) {
        if (psaTriggerMonitor.ExecutedTriggers.contains('psaProjectTriggerHandlerAfterInsert')) {
          System.debug('Skipping psaProjectTriggerHandlerAfterInsert bulkAfter method due to trigger recursion prevention');
          return;
        }
        psaTriggerMonitor.ExecutedTriggers.add('psaProjectTriggerHandlerAfterInsert');
        Set<Id> acctIds = new Set<Id> ();
        Set<Id> projIds = new Set<Id> ();
        for (SObject so : Trigger.new) {
          pse__Proj__c proj = (pse__Proj__c) so;
          projIds.add(proj.Id);
          //Add both the customer and billing accounts to our list of account IDs to retrieve
          if (proj.PSA_Customer_Account__c != null) {
            acctIds.add(proj.PSA_Customer_Account__c);
          }
          if (proj.Pse__Account__c != null) {
            acctIds.add(proj.PSE__Account__c);
          }
  
          System.debug('Acctids: ' + acctIds);
        }
  
        List<pse__Resource_Request__c> resRequests = new List<pse__Resource_Request__c> ();
        List<pse__Assignment__c> assignments = new List<pse__Assignment__c> ();
        if (projIds.size() > 0) {
          resRequests = [Select Id, pse__Start_Date__c, pse__End_Date__c, pse__Project__c,pse__Status__c,pse__Project__r.pse__Project_Type__c from pse__Resource_Request__c where pse__Project__c in :projIds];
          for (pse__Resource_Request__c rr : resRequests) {
            Id projId = rr.pse__Project__c;
            if (projId != null) {
              List<pse__Resource_Request__c> existing = resReqMap.get(projId);
              if (existing == null) {
                existing = new List<pse__Resource_Request__c> ();
              }
              existing.add(rr);
              resReqMap.put(projId, existing);
            }
          }
  
          newProjMap = new Map<Id, pse__Proj__c> ([Select ID, pse__Project_Manager__r.pse__Salesforce_User__c from pse__Proj__c where ID in :projIds]);
  
          List<pse__Billing_Event__c> bes = [Select ID, pse__Is_Released__c, pse__PRoject__c from pse__Billing_Event__c where pse__Project__c in :projIds];
          for (pse__Billing_Event__c be : bes) {
            List<pse__Billing_Event__c> exist = beMAp.get(be.pse__PRoject__c) != null ? beMap.get(be.pse__Project__c) : new List<pse__Billing_Event__c> ();
            exist.add(be);
            beMap.put(be.pse__Project__c, exist);
          }
  
          Set<Id> schedIds = new Set<Id> ();
          assignments = [Select Id, pse__Schedule__c, pse__Start_Date__c, pse__End_Date__c, pse__Project__c from pse__Assignment__c where pse__Project__c in :projIds];
          for (pse__Assignment__c a : assignments) {
            Id projId = a.pse__Project__c;
            if (projId != null) {
              List<pse__Assignment__c> existing = assignmentMap.get(projId);
              if (existing == null) {
                existing = new List<pse__Assignment__c> ();
              }
              existing.add(a);
              assignmentMap.put(projId, existing);
            }
            Id schedule = a.pse__Schedule__c;
            if (schedule != null) {
              schedIds.add(schedule);
            }
          }
  
          assignmentToSched = new Map<Id, pse__Schedule__c> ([Select Id, pse__Start_Date__c, pse__End_Date__c from pse__Schedule__c where id in :schedIds]);
        }
        List<Account> extraAccounts =
        [SELECT Id, ParentId, BillingStreet, BillingCity, BillingState, BillingPostalCode, BillingCountry
        from Account
        where ParentId in : acctIds
        ];
        if (extraAccounts != null && extraAccounts.size() > 0) {
          for (Account a : extraAccounts) {
            acctIds.add(a.id);
  
            Id parent = a.ParentId;
            List<Account> children = childAccounts.get(parent);
            if (children == null) {
              children = new List<Account> ();
            }
            children.add(a);
            childAccounts.put(parent, children);
          }
        }
  
        //Retrieve our map of Accounts that contain our billing addresses
        if (acctIds.size() > 0) {
          System.debug(LoggingLevel.ERROR, 'Account ids was > 0');
          Set<Id> recordIds = new Set<Id> ();
          List<RecordType> recordTypeIds = [Select id from RecordType where SObjectType = 'Account' and(Name = 'Customer' OR Name = 'Partner')];
          for (RecordType rt : recordtypeIds) {
            recordIds.add(rt.id);
          }
          System.debug(LoggingLevel.ERROR, 'record type ids was: ' + recordIds);
          List<Account> accts = [Select ID, Name, RecordType.Name, RecordTypeId, BillingCity, BillingState, BillingStreet, BillingCountry, BillingPostalCode from Account where Id in :acctIds];
          for (Account next : accts) {
            System.debug('**** ' + next.recordTypeId);
            if (recordIds.contains(next.recordTypeId)) {
              System.debug('**** Added to map');
              accounts.put(next.id, next);
            }
          }
          System.debug('**** Accounts is: ' + accounts);
        }
        // Retrieve the projects that will have project location objects associated with them
        for (SObject so : Trigger.new) {
          pse__Proj__c proj = (pse__Proj__c) so;
  
          //GMM 7/10 - Removed if statement below to add all projects, not just customer projects
          //if(proj.pse__Project_Type__c  == 'Customer Project'){
          //System.debug('**** Had to add the project');
          projToAddLocations.add(proj.Id);
          //}
        }
  
        List<pse__Proj__c> projectsForLocations = [SELECT id,
                                                   pse__Account__c,
                                                   PSA_Customer_Account__c,
                                                   pse__Start_Date__c,
                                                   pse__End_Date__c,
                                                   pse__Project_Type__c
                                                   FROM pse__Proj__c
                                                   WHERE id IN :projToAddLocations];
  
        if (projectsForLocations != null) {
          //System.debug(LoggingLevel.ERROR, '**** WASNT NULL');
          for (pse__Proj__c proj : projectsForLocations) {
            Set<Id> addedAccounts = new Set<Id> ();
            addressesAdded = new Set<String> ();
            //If the project Billing Account is not null, retrieve its address and create a project location
            if (proj.pse__Account__c != null) {
              Account billAccount = accounts.get(proj.pse__Account__c);
  
              if (billAccount != null) {
                //System.debug(LoggingLevel.ERROR, '**** Had to add location');
                addLocation(proj, billAccount);
                addedAccounts.add(billAccount.id);
  
              }
  
            }
            //If the project Customer Account is not null, retrieve its address and create a project location
            if (proj.PSA_Customer_Account__c != null) {
              Account custAccount = accounts.get(proj.PSA_Customer_Account__c);
              if (custAccount != null && !addedAccounts.contains(custAccount.id)) {
                addLocation(proj, custAccount);
                addedAccounts.add(custAccount.id);
              }
            }
  
            List<Account> billChildren = childAccounts.get(proj.pse__Account__c);
            List<Account> custChildren = childAccounts.get(proj.PSA_Customer_Account__c);
  
            if (billChildren != null && billChildren.size() > 0) {
              for (Account acct : billChildren) {
                if (!addedAccounts.contains(acct.id)) {
                  addLocation(proj, acct);
                  addedAccounts.add(acct.id);
                }
              }
            }
  
            if (custChildren != null && custChildren.size() > 0) {
              for (Account acct : custChildren) {
                if (!addedAccounts.contains(acct.id)) {
                  addLocation(proj, acct);
                  addedAccounts.add(acct.id);
                }
              }
            }
  
            //Create a home location
            pse__Project_Location__c proj_location = new pse__Project_Location__c();
            proj_location.pse__Project__c = proj.id;
            proj_location.pse__Description__c = 'Home Location';
            proj_location.Name = proj_location.pse__Description__c;
            proj_location.pse__Start_Date__c = proj.pse__Start_Date__c;
            proj_location.pse__End_Date__c = proj.pse__End_Date__c;
            projLocations.add(proj_location);
  
          }
          //System.debug(LoggingLevel.Error, '*** AfterInsert: Number of project locations to create: ' + projLocations.size());    
        }
        // Added by Hari to clone Rate set from a template.
        Set<Id> RatesetIds = new Set<Id> ();
        List<PSA_Rate__c> RatesLst = new List<PSA_Rate__c> ();
  
        for (SObject so : Trigger.new) {
          pse__Proj__c proj = (pse__Proj__c) so;
          if (proj.PSA_Project_Rate_Set_Custom__c != null) {
            id Rateset = (id) proj.PSA_Project_Rate_Set_Custom__c;
            RatesetIds.add(Rateset);
          }
        }
        system.debug('Rateset ids :' + RatesetIds.size());
  
        if (RatesetIds.size() > 0) {
          RateSetMap = new Map<id, PSA_Rate_Set__c> ([Select Id, Name, PSA_Account__c, PSA_Is_Global__c, PSA_Project__c, Requires_Ops_Review__c from PSA_Rate_Set__c where Id in :RatesetIds]);
          System.debug('*** The RateSets related to the projects: ' + RateSetMap);
          RatesLst = [select id, name, PSA_Average_Cost_Rate__c, PSA_Billing_Level__c, PSA_Bill_Rate_Amount__c, PSA_Start_Date__c, PSA_End_Date__c, PSA_Bill_Rate_Set__c, Is_Updated__c from PSA_Rate__c where PSA_Bill_Rate_Set__c IN :RatesetIds];
        }
  
        if (RatesLst != null && RatesLst.size() > 0)
        {
          for (PSA_Rate__c rat : RatesLst)
          {
            if (RatesMap.containsKey(rat.PSA_Bill_Rate_Set__c))
            {
              List<PSA_Rate__c> RLst = RatesMap.get(rat.PSA_Bill_Rate_Set__c);
              RLst.add(rat);
              RatesMap.put(rat.PSA_Bill_Rate_Set__c, RLst);
            }
            else
            {
              RatesMap.put(rat.PSA_Bill_Rate_Set__c, new List<PSA_Rate__c> { rat });
            }
          }
        }
      }
      if (trigger.isUpdate) {
        if (psaTriggerMonitor.ExecutedTriggers.contains('psaProjectTriggerHandlerAfterUpdate')) {
          System.debug('Skipping psaProjectTriggerHandlerAfterUpdate bulkAfter method due to trigger recursion prevention');
          return;
        }
       
        
        map<id,pse__Proj__c> projMap = new map <id,pse__Proj__c>();
        psaTriggerMonitor.ExecutedTriggers.add('psaProjectTriggerHandlerAfterUpdate');
        Set<Id> acctIds = new Set<Id> ();
        Set<Id> projIds = new Set<Id> ();
        for (SObject so : Trigger.new) {
          pse__Proj__c proj = (pse__Proj__c) so;
          pse__Proj__c oldproj = (pse__Proj__c) trigger.oldmap.get(so.id);
  
          if(proj.pse__Start_Date__c != oldproj.pse__Start_Date__c || proj.pse__End_Date__c != oldproj.pse__End_Date__c){
            projMap.put(proj.id,proj);
          }
          
          projIds.add(proj.Id);
          //Add both the customer and billing accounts to our list of account IDs to retrieve
          if (proj.PSA_Customer_Account__c != null) {
            acctIds.add(proj.PSA_Customer_Account__c);
          }
          if (proj.Pse__Account__c != null) {
            acctIds.add(proj.PSE__Account__c);
          }
          System.debug('Acctids: ' + acctIds);
  
          //Hari updated 3/27/2019 : CHG0032297        
          /*defaultAssignmentResourceIds.add(proj.PSA_CIM__c);
          defaultAssignmentResourceIds.add(proj.PSA_PIA__c);
          defaultAssignmentResourceIds.add(proj.PSA_Director__c);*/
  
        }
  
        List<pse__Resource_Request__c> resRequests = new List<pse__Resource_Request__c> ();
        List<pse__Assignment__c> assignments = new List<pse__Assignment__c> ();
        List<Assets_Involved__c> assetsInvolved = new List<Assets_Involved__c> ();
        set<id> resourceRequestIds = new set<id> ();
        if (projIds.size() > 0) {
          resRequests = [Select Id, name, pse__Status__c, pse__Preferred_Schedule__c, pse__Start_Date__c, pse__End_Date__c, pse__Project__c, pse__Assignment__c, RMO_Change_Reason__c,pse__Project__r.pse__Project_Type__c from pse__Resource_Request__c where pse__Project__c in :projIds];
          for (pse__Resource_Request__c rr : resRequests) {
            Id projId = rr.pse__Project__c;
            resourceRequestIds.add(rr.id);
            if (projId != null) {
              List<pse__Resource_Request__c> existing = resReqMap.get(projId);
              if (existing == null) {
                existing = new List<pse__Resource_Request__c> ();
              }
              existing.add(rr);
              resReqMap.put(projId, existing);
              //hari updated 1/26/2018 : CHG0030554
              List<pse__Resource_Request__c> exist = resReqCancelMap.get(rr.pse__PRoject__c) != null ? resReqCancelMap.get(rr.pse__Project__c) : new List<pse__Resource_Request__c> ();
              exist.add(rr);
              resReqCancelMap.put(projId, exist);
            }
          }
  
          newProjMap = new Map<Id, pse__Proj__c> ([Select ID, pse__Project_Manager__r.pse__Salesforce_User__c from pse__Proj__c where ID in :projIds]);
  
          List<pse__Billing_Event__c> bes = [Select ID, pse__Is_Released__c, pse__PRoject__c from pse__Billing_Event__c where pse__Project__c in :projIds];
          for (pse__Billing_Event__c be : bes) {
            List<pse__Billing_Event__c> exist = beMAp.get(be.pse__PRoject__c) != null ? beMap.get(be.pse__Project__c) : new List<pse__Billing_Event__c> ();
            exist.add(be);
            beMap.put(be.pse__Project__c, exist);
          }
  
          /* //hari updated 1/26/2018 : CHG0030554
            List<pse__Resource_Request__c> reqs = [Select ID,name,pse__Status__c,pse__Project__c,pse__Assignment__c,RMO_Change_Reason__c from pse__Resource_Request__c where pse__Project__c in :projIds];
            for(pse__Resource_Request__c req : reqs){
            List<pse__Resource_Request__c> exist = resReqCancelMap.get(req.pse__PRoject__c) != null ? resReqCancelMap.get(req.pse__Project__c) : new List<pse__Resource_Request__c>();
            exist.add(req);
            resReqCancelMap.put(req.pse__Project__c, exist);
            } */
  
          //hari updated 3/28/2018 : CHG0030532
          assetsInvolved = [Select id, name, Account__c, Asset__c, Major_Version__c, Parent_Asset__c, Project__c, Release_Type__c, Target_Go_Live_Date__c,
                            Upgrade_Involved__c from Assets_Involved__c where Project__c in :projIds];
          for (Assets_Involved__c asI : assetsInvolved) {
            List<Assets_Involved__c> existing = assetsInvolvedMap.get(asI.Project__c);
            if (existing == null) {
              existing = new List<Assets_Involved__c> ();
            }
            existing.add(asI);
            assetsInvolvedMap.put(asI.Project__c, existing);
          }
  
          Set<Id> schedIds = new Set<Id> ();
          assignments = [Select Id, pse__Schedule__c, pse__Start_Date__c, pse__End_Date__c, pse__Project__c from pse__Assignment__c where pse__Project__c in :projIds];
          for (pse__Assignment__c a : assignments) {
            Id projId = a.pse__Project__c;
            if (projId != null) {
              List<pse__Assignment__c> existing = assignmentMap.get(projId);
              if (existing == null) {
                existing = new List<pse__Assignment__c> ();
              }
              existing.add(a);
              assignmentMap.put(projId, existing);
            }
            Id schedule = a.pse__Schedule__c;
            if (schedule != null) {
              schedIds.add(schedule);
            }
          }
  
          assignmentToSched = new Map<Id, pse__Schedule__c> ([Select Id, pse__Start_Date__c, pse__End_Date__c from pse__Schedule__c where id in :schedIds]);
  
          //Hari updated 3/27/2019 : CHG0032297
          /*if (defaultAssignmentResourceIds.size() > 0) {
            defaultAssignmentResources = [select id, name, pse__Resource_Role__c, PSA_Billing_Level__c, pse__Default_Cost_Rate__c, pse__Is_Resource__c, PSA_PS_Level__c from Contact where id in :defaultAssignmentResourceIds];
          }*/
          
          if (!projMap.isEmpty() ) {
  
            //updateRRScheduleDates(resRequests,projMap);
          }
          
  
        }
        //SD 03/29 - FFPSA-131 START
        for (SObject so : Trigger.new) {
        pse__Proj__c proj = (pse__Proj__c) so;
        pse__Proj__c oldproj = (pse__Proj__c) trigger.oldmap.get(so.id);
          if(proj.PSA_Current_Go_Live_Date__c != oldproj.PSA_Current_Go_Live_Date__c) {
            goLiveDateUpdateProjectMap.put(proj.Id,proj.PSA_Current_Go_Live_Date__c);
          }
        }
      }
    }
  
    /**************************************************************************************
      // Name        : beforeInsert
      // Description : This method is called iteratively for each record to be inserted 
      //               during a BEFORE trigger. Never execute any SOQL/SOSL etc in this and 
      //               other iterative methods.
     ***************************************************************************************/
    public void beforeInsert(SObject so) {
      System.debug('Inserting a project');
      pse__Proj__c project = (pse__Proj__c) so;
      Account a = accounts.get(project.pse__account__c);
      Account customer = accounts.get(project.PSA_Customer_Account__c);
      String shortName = '';
      if (a != null) {
        //System.debug('Project had a billing account');
        if (project.psa_Customer_Account__c == null) {
          //System.debug('Updating customer account');
          project.psa_Customer_Account__c = a.id;
          shortName = a.CS_Account_Short_Name__c;
        }
        else if (project.PSA_Customer_Account__c != null) {
          shortName = customer.CS_Account_Short_Name__c;
        }
      }
      //Hari updated 10/2/2018 :  CHG0031210
      if (project.PSA_Project_Release__c != null || project.PSA_Project_Release__c != '') {
        shortName += '-' + project.PSA_Project_Release__c;
      }
      if (project.PSA_Product_Line__c != null || project.PSA_Product_Line__c != '') {
        String prjProdName = project.PSA_Product_Line__c;
        if (String.isNotBlank(prjProdName)) {
          if (prjProdName.containsIgnoreCase(';')) {
            List<String> parts = prjProdName.split(';');
            parts.sort();
            prjProdName = String.join(parts, '-');
          }
          System.debug('*** before insert Product Lines: ' + prjProdName);
          if (ProductsMap != null) {
            Product2 prod = ProductsMap.get(prjProdName);
            System.debug('*** before insert Product: ' + prod);
            if (prod != null) {
              shortName += '-' + prod.ProductCode;
            }
          }
        }
      }
  
      if (shortName != '') {
        project.PSA_Internal_Project_Name__c = shortName;
      }
     
      if(project.Related_Project__c != NULL && project.PSA_Services_Product__c == 'Cloud Assurances' && relatedProjectGoLiveDateMap.size()> 0) {
        project.PSA_Current_Go_Live_Date__c = relatedProjectGoLiveDateMap.get(project.Related_Project__c);
      }
        
    }
  
    /**************************************************************************************
      // Name        : beforeUpdate
      // Description : This method is called iteratively for each record to be updated 
      //               during a BEFORE trigger.
     ***************************************************************************************/
    public void beforeUpdate(SObject oldSo, SObject so) {
      pse__Proj__c proj_old = (pse__Proj__c) oldSo;
      pse__Proj__c proj_new = (pse__Proj__c) so;
  
      if(proj_old.PSA_Current_Go_Live_Date__c != proj_new.PSA_Current_Go_Live_Date__c && psaAssetsInvolvedTriggerHandler.manuallyUpdating == TRUE){
          List<Assets_Involved__c> hasAssets = projToAssets.get(proj_new.id);
          if(hasAssets != null && hasAssets.size() > 0){
            proj_new.addError('You cannot manually edit the Current Go-Live Date if there is an Asset Involved with a Go-Live Date already attached');
            proj_new.PSA_Current_Go_Live_Date__c = proj_old.PSA_Current_Go_Live_Date__c;
          }
      }
      //If the stage has changed to in progress, and the project manager has not been assigned to 'owner' yet
      if ((proj_old.pse__Stage__c != 'In Progress' && proj_new.pse__Stage__c == 'In Progress')
          && proj_new.OwnerID != proj_new.pse__Project_Manager__c) {
        // Assign the project Manager to project owner now that project is in progress...
        Id sfdc_user = pm_resource_sfdcUserMap.get(proj_new.pse__Project_Manager__c);
        if (sfdc_user != null) {
          proj_new.OwnerID = sfdc_user;
        }
      }
      boolean isCustomer = proj_new.pse__Project_Type__c == 'Customer Project';
      validateFields(proj_new, isCustomer);
      /*if(proj_old.PSA_BR_Billing_Rules_Status__c != proj_new.PSA_BR_Billing_Rules_Status__c && 
        proj_new.PSA_BR_Billing_Rules_Status__c == 'Accepted') {
        if(expensePACs.size() > 1 && (proj_new.PSA_BR_Expenses_Billing_Type__c == 'Percent of Services' || proj_new.PSA_BR_Expenses_Billing_Type__c == 'Flat Amount Per Day')){
        proj_new.addError('For Expenses Billing Types of Percent of Services or Flat Amount Per Day, only one account credit of type Expenses is allowed.');
        }
        }*/
  
      //If the Billing Rules Status has been set to Accepted, populate the Billing Rules Status History fields
      if (proj_old.PSA_BR_Billing_Rules_Status__c != proj_new.PSA_BR_Billing_Rules_Status__c &&
          proj_new.PSA_BR_Billing_Rules_Status__c == 'Accepted') {
          proj_new.Billing_Rules_Accepted_User__c = UserInfo.getName();
        //proj_new.PSA_Billing_Rules_Accepted_Date__c = DateTime.now();
      }
  
      //Hari updated 10/2/2018 :  CHG0031210
      if (proj_old.PSA_Customer_Account__c != proj_new.PSA_Customer_Account__c || proj_old.PSA_Project_Release__c != proj_new.PSA_Project_Release__c ||
          proj_old.PSA_Product_Line__c != proj_new.PSA_Product_Line__c) {
        Account customer = accounts.get(proj_new.PSA_Customer_Account__c);
        String shortName = '';
        if (proj_new.psa_Customer_Account__c != null) {
          shortName = customer.CS_Account_Short_Name__c;
        }
        if (proj_new.PSA_Project_Release__c != null || proj_new.PSA_Project_Release__c != '') {
          shortName += '-' + proj_new.PSA_Project_Release__c;
        }
        if (proj_new.PSA_Product_Line__c != null || proj_new.PSA_Product_Line__c != '') {
          String prjProdName = proj_new.PSA_Product_Line__c;
          if (String.isNotBlank(prjProdName)) {
            if (prjProdName.containsIgnoreCase(';')) {
              List<String> parts = prjProdName.split(';');
              parts.sort();
              prjProdName = String.join(parts, '-');
            }
            System.debug('*** before update Product Lines: ' + prjProdName);
            if (ProductsMap != null) {
              Product2 prod = ProductsMap.get(prjProdName);
              System.debug('*** before update Product: ' + prod);
              if (prod != null) {
                shortName += '-' + prod.ProductCode;
              }
            }
          }
        }
  
        if (shortName != '') {
          proj_new.PSA_Internal_Project_Name__c = shortName;
        }
      }
      
      if(relatedProjectGoLiveDateMap.size()> 0) {
        if(proj_new.Related_Project__c != NULL && proj_new.PSA_Services_Product__c == 'Cloud Assurances' && proj_new.Related_Project__c != proj_old.Related_Project__c) {
          proj_new.PSA_Current_Go_Live_Date__c = relatedProjectGoLiveDateMap.get(proj_new.Related_Project__c);
        }
      }
    }
  
    /**************************************************************************************
      // Name        : beforeDelete
      // Description : This method is called iteratively for each record to be deleted 
      //               during a BEFORE trigger.
     ***************************************************************************************/
    public void beforeDelete(SObject so) { }
  
    /**************************************************************************************
      // Name        : afterInsert
      // Description : This method is called iteratively for each record inserted 
      //               during an AFTER trigger. Always put field validation in the 'After' 
      //               methods in case another trigger has modified any values. The record 
      //               is 'read only' by this point.
     ***************************************************************************************/
    public void afterInsert(SObject so) {
  
      pse__Proj__c project = (pse__Proj__c) so;
  
      //Added by Hari to clone the Rateset.
      PSA_Rate_Set__c oldRateSet = RateSetMap.get(project.PSA_Project_Rate_Set_Custom__c);
      PSA_Rate_Set__c newrateset = new PSA_Rate_Set__c();
      if (oldRateSet != null)
      {
        newrateset.Name = project.pse__Project_ID__c + ' - Rate Set';
        newrateset.currencyIsoCode = oldRateSet.currencyIsoCode;
        newrateset.PSA_Project__c = project.Id;
        newrateset.PSA_Is_Global__c = false;
        insert newrateset;
      }
  
      List<PSA_Rate__c> existingRatesLst = RatesMap.get(project.PSA_Project_Rate_Set_Custom__c);
      List<PSA_Rate__c> newRatesLst = new List<PSA_Rate__c> ();
  
      if (existingRatesLst != null && existingRatesLst.size() > 0)
      {
        for (PSA_Rate__c ra : existingRatesLst)
        {
          PSA_Rate__c newRate = new PSA_Rate__c();
          newRate.PSA_Bill_Rate_Set__c = newrateset.Id;
          newRate.PSA_Average_Cost_Rate__c = ra.PSA_Average_Cost_Rate__c;
          newRate.PSA_Billing_Level__c = ra.PSA_Billing_Level__c;
          newRate.PSA_Bill_Rate_Amount__c = ra.PSA_Bill_Rate_Amount__c;
          newRate.PSA_End_Date__c = ra.PSA_End_Date__c;
          newRate.Is_Updated__c = ra.Is_Updated__c;
          newRate.PSA_Start_Date__c = ra.PSA_Start_Date__c;
          newRatesLst.add(newRate);
        }
      }
      if (newRatesLst.size() > 0)
      insert newRatesLst;
    }
  
    /**************************************************************************************
      // Name        : afterUpdate
      // Description : This method is called iteratively for each record updated 
      //               during an AFTER trigger.
     ***************************************************************************************/
    public void afterUpdate(SObject oldSo, SObject so) {
      pse__Proj__c newProj = (pse__Proj__c) so;
      pse__Proj__c oldProj = (pse__Proj__c) oldSo;
  
      //If the start or end date has changed
      if (newProj.pse__Start_Date__c != oldProj.pse__Start_Date__c ||
          newProj.pse__End_Date__c != oldProj.pse__End_Date__c) {
        projectDatesUpdated.put(newProj.id, newProj);
      }
  
      if (oldProj.pse__Project_Manager__c != newProj.pse__Project_Manager__c) {
        List<pse__Billing_Event__c> existing = beMap.get(newProj.id);
        if (existing != null) {
          for (pse__Billing_Event__c be : existing) {
            if (!be.pse__is_Released__c) {
              be.PSA_PM_User__c = newProjMap.get(newProj.id).pse__Project_Manager__r.pse__Salesforce_User__c;
              besToUpdate.add(be);
            }
          }
        }
  
      }
  
      if (oldProj.pse__Stage__c == 'Draft' && newProj.pse__Stage__c == 'Draft' &&
          oldProj.pse__Start_Date__c != newProj.pse__Start_Date__c) {
        Date oldS = oldProj.pse__Start_Date__c;
        Date newS = newProj.pse__Start_Date__c;
        Integer difference = 0;
        // GMM 7/13: Added line below to check for null values 
        if (oldS != null && newS != null)
        {
          if (oldS<newS) {
            difference = netWorkDay(oldS, newS);
          }
          else {
            difference = netWorkDay(newS, oldS) * - 1;
            //System.debug('Work day difference is: '+difference);
  
          }
          updateRRandAssignments(newProj.id, oldS, difference);
        }
      }
  
      //hari updated 1/26/2018 : CHG0030554        
      if (oldProj.pse__Stage__c != newProj.pse__Stage__c && (oldProj.pse__Stage__c == 'Draft' || oldProj.pse__Stage__c == 'Open - No GW Involved') && newProj.pse__Stage__c == 'Canceled') {
        List<pse__Resource_Request__c> existing = resReqCancelMap.get(newProj.id);
        if (existing != null) {
          for (pse__Resource_Request__c req : existing) {
            req.pse__Status__c = 'Cancelled';
            req.RMO_Change_Reason__c = 'Project Cancelled';
            resReqCancelLst.add(req);
          }
        }
      }
  
      //hari updated 3/28/2018 : CHG0030532
      if (oldProj.PSA_Current_Go_Live_Date__c != newProj.PSA_Current_Go_Live_Date__c) {
        List<Assets_Involved__c> existing = assetsInvolvedMap.get(newProj.id);
        if (existing != null) {
          for (Assets_Involved__c asI : existing) {
            if (asI.Target_Go_Live_Date__c == null && newProj.PSA_Current_Go_Live_Date__c != null) {
              // if(oldProj.PSA_Current_Go_Live_Date__c == asI.Target_Go_Live_Date__c){
              asI.Target_Go_Live_Date__c = newProj.PSA_Current_Go_Live_Date__c;
              assetsInvolvedTarget.add(asI);
            }
          }
        }
      }
      
      if(goLiveDateUpdateProjectMap.size() >0) {
        for(pse__Proj__c allProj: [Select Id,Related_Project__c,PSA_Current_Go_Live_Date__c,PSA_Services_Product__c
                                      from pse__Proj__c
                                      where Related_Project__c in:goLiveDateUpdateProjectMap.keyset() and PSA_Services_Product__c = 'Cloud Assurances' ]) {
          allProj.PSA_Current_Go_Live_Date__c = goLiveDateUpdateProjectMap.get(allProj.Related_Project__c);  
          updateProjectGoLive.add(allProj);
        }
      }
  
      //Hari updated 2/6/2018 :  CHG0032297
      /*if (oldProj.pse__Stage__c != newProj.pse__Stage__c && (oldProj.pse__Stage__c == 'Draft' || oldProj.pse__Stage__c == 'Open - No GW Involved' || oldProj.pse__Stage__c == 'PM Review') && newProj.pse__Stage__c == 'Operations Review') {
        defaultAssignmentProjects.add(newProj);
        if (defaultAssignmentResources.size()> 0) {
          for (Contact con : defaultAssignmentResources) {
            if (con.Id == newProj.PSA_CIM__c || con.Id == newProj.PSA_PIA__c || con.Id == newProj.PSA_Director__c) {
              pse__Schedule__c aSched = new pse__Schedule__c();
              aSched.pse__Start_Date__c = newProj.pse__Start_Date__c;
              aSched.pse__End_Date__c = newProj.pse__End_Date__c;
              aSched.pse__Scheduled_Days__c = 0;
              aSched.pse__Scheduled_Hours__c = 0;
              aSched.pse__Monday_Hours__c = 0;
              aSched.pse__Tuesday_Hours__c = 0;
              aSched.pse__Wednesday_Hours__c = 0;
              aSched.pse__Thursday_Hours__c = 0;
              aSched.pse__Friday_Hours__c = 0;
              aSched.pse__Saturday_Hours__c = 0;
              aSched.pse__Sunday_Hours__c = 0;
              defaultAssignmentSchedules.add(aSched);
            }
          }
        }
      }*/
    }
  
    /**************************************************************************************
      // Name        : afterDelete
      // Description : This method is called iteratively for each record deleted 
      //               during an AFTER trigger.
      // Arguments   : SObject so - the object that initiated the trigger
     ***************************************************************************************/
    public void afterDelete(SObject so) { }
  
    /**************************************************************************************
      // Name        : andFinally
      // Description : This method is called once all records have been processed by the 
      //               trigger. Use this method to accomplish any final operations such as
      //               creation or updates of other records.
      // Arguments   : SObject so - the object that initiated the trigger
     ***************************************************************************************/
    public void andFinally() {
  
      if (trigger.isInsert && trigger.isAfter) {
        System.debug('*** Finally: Number of project locations to create: ' + projLocations.size());
        if (projLocations.size() > 0) {
          insert projLocations;
          //System.debug('*** Inserted project locations: ' + projLocations.size());
        }
      }
      list<id> projIDs = new list<Id>();
      if ((trigger.isUpdate) && trigger.isAfter){
            for (SObject so : Trigger.new) {
                pse__Proj__c exp = (pse__Proj__c) so;
                pse__Proj__c projold = (pse__Proj__c) trigger.oldmap.get(exp.id);
                if(exp.PSA_CIM__c != projold.PSA_CIM__c || exp.PSA_Director__c != projold.PSA_Director__c || exp.PSA_VP__c != projold.PSA_VP__c
                    || exp.pse__Project_Manager__c != projold.pse__Project_Manager__c){
                    projIDs.add(exp.id);

                }           
            }

        }
        if(projIDs.size() >0){
            UpsertExpenseSharing(projIDs);
        }

      //Update applicable Project Locations
      if (projectDatesUpdated.size() > 0) {
        handleDateChange();
  
        System.debug('*** Finally: Number of project locations dates to update: ' + locationsUpdate.size());
        if (locationsUpdate.size() > 0) {
          update locationsUpdate;
          //System.debug('*** Updated project locations: ' + locationsUpdate.size());
        }
      }
      if (rrToUpdate.size() > 0) {
        System.debug('*** Finally: Updated rrs');
        update rrToUpdate;
  
      }
      if (schedToUpdate.size() > 0) {
        System.debug('*** Finally: Updating the schedules');
        update schedToUpdate;
      }
      if (besToUpdate.size() > 0) {
        update besToUpdate;
      }
  
      //hari updated 1/26/2018 : CHG0030554 : update RR's to Cancelled state.
      if (resReqCancelLst.size() > 0) {
        update resReqCancelLst;
      }
  
      //hari updated 3/28/2018 : CHG0030532  -- update Assets Involved Target Go Live date.
      if (assetsInvolvedTarget.size() > 0) {
        update assetsInvolvedTarget;
      }
      
      if(updateProjectGoLive.size()> 0) {
        update updateProjectGoLive;
      }
  
      //Hari updated 3/27/2019 : CHG0032297
      /*if (defaultAssignmentSchedules.size() > 0) {
        insert defaultAssignmentSchedules;
  
        if (defaultAssignmentResources.size() > 0 && defaultAssignmentProjects.size() > 0) {
          integer i = 0;
          for (pse__Proj__c project : defaultAssignmentProjects) {
            for (Contact resource : defaultAssignmentResources) {
              if (resource.Id == project.PSA_CIM__c || resource.Id == project.PSA_PIA__c || resource.Id == project.PSA_Director__c) {
                pse__Assignment__c assg = new pse__Assignment__c();
                assg.pse__Resource__c = resource.Id;
                assg.pse__Role__c = resource.pse__Resource_Role__c;
                assg.PSA_Start_Date__c = project.pse__Start_Date__c;
                assg.PSA_End_Date__c = project.pse__End_Date__c;
                assg.pse__Use_Resource_Default_Cost_Rate__c = true;
                assg.pse__Cost_Rate_Currency_Code__c = project.CurrencyIsoCode;
                assg.pse__Use_Project_Currency_For_Resource_Cost__c = true;
                assg.pse__Is_Billable__c = project.pse__Is_Billable__c;
                assg.pse__Project__c = project.Id;
                assg.PSA_Billing_Level__c = resource.PSA_Billing_Level__c;
                assg.PSA_Rate_Set__c = project.PSA_Project_Rate_Set__c;
                if(resource.Id == project.PSA_CIM__c) {
                  assg.PSA_Project_Role__c = 'Engagement Manager';
                }
                if(resource.Id == project.PSA_PIA__c) {
                  assg.PSA_Project_Role__c = 'Enterprise Architect';
                }
                if(resource.Id == project.PSA_Director__c) {
                  assg.PSA_Project_Role__c = 'Portfolio Director';
                }
                assg.pse__Bill_Rate__c = 0;
                //assg.PSA_Override_Bill_Rate__c = true;
                assg.PSA_Rate_Needs_Review__c = false;
                assg.pse__Closed_for_Time_Entry__c = false;
                assg.pse__Closed_for_Expense_Entry__c = false;
                assg.pse__Schedule__c = defaultAssignmentSchedules[i].Id;
                i++;
                defaultAssignments.add(assg);
              }
            }
          }
        }
      }
      if (defaultAssignments.size() > 0) {
        insert defaultAssignments;
      }*/
  
      /*
        if (psaTriggerMonitor.ExecutedTriggers.contains('psaProjectTriggerHandler')) {
        System.debug('Skipping psaProjectTriggerHandler andFinally() method due to trigger recursion prevention');
        return;
        }
       
       
        psaTriggerMonitor.ExecutedTriggers.add('psaProjectTriggerHandler');
       */
    }
  
    /**************************************************************************************
      // Name         : handleDateChange
      // Description  : Update the start and/or end dates for related project locations if the 
      //                  start and/or end date on the project has changed
      // Revisions    : 2015-03-01    Schwartz    Initial Version 
      //              : 2015-04-27    Klassen     Code refactor
     ***************************************************************************************/
    private void handleDateChange() {
      //Obtain any project locations associated with the projects whose dates have changed
      List<pse__Project_Location__c> locations =
      [SELECT pse__Start_Date__c, pse__End_Date__c, pse__Project__c
      From pse__Project_Location__c
      Where pse__Project__c in : projectDatesUpdated.keySet()
      ];
      if (locations != null && locations.size() > 0) {
        for (pse__Project_Location__c loc : locations) {
          //Retrieve the project associated with the project location
          pse__Proj__c thisProj = projectDatesUpdated.get(loc.pse__Project__c);
          if (thisProj != null) {
            Date start = thisProj.pse__Start_Date__c;
            Date endDate = thisProj.pse__End_Date__c;
            loc.pse__Start_Date__c = start;
            loc.pse__End_Date__c = endDate;
            //Add the updated location to our list 
            locationsUpdate.add(loc);
          }
        }
      }
    }
  
    private void checkImplementers(pse__Proj__c proj) {
      List<PSA_Implementer__c> imps = [Select Id from PSA_Implementer__c where PSA_Project__c = :proj.id];
      if (imps == null || imps.isEmpty()) {
        throw new psaException('At least one implementer is required for a project to be set to In progress');
      }
    }
  
    /**************************************************************************************
      // Name         : addLocation
      // Description  : Add a location from an account to the project 
      // Revisions    : 2015-05-07 Spano initial version
     ***************************************************************************************/
    private void addLocation(pse__Proj__c proj, Account a) {
      String city = a.BillingCity;
      String state = a.BillingState;
      //String street = a.BillingStreet;
      String country = a.BillingCountry;
      //String code = a.BillingPostalCode;
  
      //String key = city+state+country+code;
      String key;
  
      Boolean isCustomerProject = false;
  
      if (proj.pse__Project_Type__c == 'Customer Project') {
        isCustomerProject = true;
      }
  
      if (isCustomerProject) {
        key = city + state + country;
      }
      else {
        key = state + country;
      }
  
      if (addressesAdded.contains(key)) {
        //System.debug('*** The address was contained');
        return;
      }
  
      addressesAdded.add(key);
      //System.debug('*** Added address: '+key);
  
      pse__Project_Location__c proj_location = new pse__Project_Location__c();
      proj_location.pse__Project__c = proj.id;
  
      if (isCustomerProject) {
        proj_location.pse__Description__c = city + ', ' + state + ' ' + country;
        proj_location.PSA_City__c = city;
      }
      else {
        if (state != null) {
          proj_location.pse__Description__c = country + ', ' + state;
        }
        else {
          proj_location.pse__Description__c = country;
        }
  
      }
  
      proj_location.PSA_State_Province__c = state;
  
      //proj_location.PSA_Postal_Code__c = code;
  
      proj_location.PSA_Country__c = country;
      if (state != null) {
        proj_location.PSA_State_Province__c = state;
      }
      proj_location.Name = proj_location.pse__Description__c;
      proj_location.pse__Start_Date__c = proj.pse__Start_Date__c;
      proj_location.pse__End_Date__c = proj.pse__End_Date__c;
      projLocations.add(proj_location);
    }
  
  
    /**************************************************************************************
      // Name         : netWorkDay
      // Description  : Calculate the # of work days between two dates
      // Revisions    : 
     ***************************************************************************************/
    public static integer netWorkDay(Date sdate, Date edate) {
      //System.debug('THIS IS A DEBUG');
      Datetime sDT = Datetime.newInstance(sdate.year(), sdate.month(), sdate.day());
      Datetime eDT = Datetime.newInstance(edate.year(), edate.month(), edate.day());
      integer count = 0;
      integer wDay = sdate.daysBetween(edate);
      System.debug('WDAY: ' + wDay);
  
      do {
        if (sDT.format('EEEE') == 'Saturday') {
          count++;
        }
        if (sDT.format('EEEE') == 'Sunday') {
          count++;
        }
        sDT = sDT.adddays(1);
      } while (sDT <= eDT);
  
      wDay = wDay - count;
      //System.debug('*** net days is: '+wDay);
      return wDay;
    }
  
    public static Integer daysWithWorkDays(Date start, Integer workDays) {
      if (workDays > 0) {
        Datetime nextDay = Datetime.newInstance(start.year(), start.month(), start.day() + 1);
        Integer workDayCount = 0;
        Integer totalCount = 0;
        while (workDayCount<workDays) {
          //System.debug('DAY IS: '+nextDay.format('EEEE'));
          if (nextDay.format('EEEE') == 'Saturday' || nextDay.format('EEEE') == 'Sunday') {
            totalCount++;
          }
          else {
            totalCount++;
            workDayCount++;
          }
          nextDay = nextDay.addDays(1);
        }
        //System.debug('*** Returning: '+totalCount);
        return totalCount;
      }
      else {
        Datetime nextDay = Datetime.newInstance(start.year(), start.month(), start.day() - 1);
        Integer workDayCount = 0;
        Integer totalCount = 0;
        while (workDayCount> workDays) {
          //System.debug('DAY IS: '+nextDay.format('EEEE'));
          if (nextDay.format('EEEE') == 'Saturday' || nextDay.format('EEEE') == 'Sunday') {
            totalCount--;
          }
          else {
            totalCount--;
            workDayCount--;
          }
          nextDay = nextDay.addDays(- 1);
        }
        //System.debug('*** Returning: '+totalCount);
        return totalCount;
      }
    }
  
    private void updateRRandAssignments(ID projectId, Date oldStart, Integer days) {
      List<pse__Resource_Request__c> requestsNeedingUpdate = resReqMap.get(projectId);
      List<pse__Assignment__c> assignmentsUpdate = assignmentMap.get(projectId);
  
      if (requestsNeedingUpdate != null && requestsNeedingUpdate.size() > 0) {
        for (pse__Resource_Request__c rr : requestsNeedingUpdate) {
          Date start = rr.pse__Start_Date__c;
          Date endDate = rr.pse__End_date__c;
          Integer toChangeStart = daysWithWorkDays(start, days);
          Integer toChangeEnd = daysWithWorkDays(endDate, days);
          rr.pse__Start_Date__c = start + toChangeStart;
          rr.pse__End_Date__c = rr.pse__End_Date__c + toChangeEnd;
          rrToUpdate.add(rr);
        }
      }
  
      if (assignmentsUpdate != null && assignmentsUpdate.size() > 0) {
        for (pse__Assignment__c a : assignmentsUpdate) {
          if (a.pse__Schedule__c != null) {
            pse__Schedule__c aSched = assignmentToSched.get(a.pse__Schedule__c);
            Date start = aSched.pse__Start_Date__c;
            Date endDate = aSched.pse__End_Date__c;
            Integer toChangeStart = daysWithWorkDays(start, days);
            Integer toChangeEnd = daysWithWorkDays(endDate, days);
            aSched.pse__Start_Date__c = start + toChangeStart;
            aSched.pse__End_Date__c = endDate + toChangeEnd;
            schedToUpdate.add(aSched);
          }
        }
      }
  
  
    }
  
    private void validateFields(pse__Proj__c proj, boolean isCustomer) {
      if (proj.pse__Stage__c == 'Finance Review') {
        validateFinanceReview(proj, isCustomer);
      }
      else if (proj.pse__Stage__c == 'In Progress') {
        validateInProgress(proj, isCustomer);
      }
    }
  
    private void validateInProgress(pse__Proj__c proj, boolean isCustomer) {
      String errorMessage = 'The following field(s) are missing for Stage: In Progress: ';
      boolean isError = false;
      if (proj.PSA_VSOE_Type__c == '' || proj.PSA_VSOE_Type__c == null) {
        errorMessage += 'VSOE Type';
        isError = true;
      }
  
      if (proj.currencyIsoCode == '' || proj.currencyIsoCode == null) {
        if (isError) {
          errorMessage += ', ';
        }
        errorMessage += 'Currency';
        isError = true;
      }
      if (proj.pse__Start_Date__c == null) {
        if (isError) {
          errorMessage += ', ';
        }
        errorMessage += 'Start Date';
        isError = true;
      }
      if (proj.pse__End_Date__c == null) {
        if (isError) {
          errorMessage += ', ';
        }
        errorMessage += 'End Date';
        isError = true;
      }
      if (proj.pse__Region__c == null) {
        if (isError) {
          errorMessage += ', ';
        }
        errorMessage += 'Region';
        isError = true;
      }
      if (proj.pse__Practice__c == null) {
        if (isError) {
          errorMessage += ', ';
        }
        errorMessage += 'Practice';
        isError = true;
      }
      if (proj.pse__Group__c == null) {
        if (isError) {
          errorMessage += ', ';
        }
        errorMessage += 'Group';
        isError = true;
      }
      if (proj.pse__Project_Type__c == null || proj.pse__Project_Type__c == '') {
        if (isError) {
          errorMessage += ', ';
        }
        errorMessage += 'Project Type';
        isError = true;
      }
      if (proj.PSA_BR_Expenses_Billing_Type__c == null || proj.PSA_BR_Expenses_Billing_Type__c == '') {
        if (isError) {
          errorMessage += ', ';
        }
        errorMessage += 'Expenses Billing Type';
        isError = true;
      }
      if (proj.pse__Billing_Type__c == null || proj.pse__Billing_Type__c == '') {
        if (isError) {
          errorMessage += ', ';
        }
        errorMessage += 'Services Billing Type';
        isError = true;
      }
      /*
      if (proj.PSA_Revenue_Forecast_Model__c == null || proj.PSA_Revenue_Forecast_Model__c == '') {
        if (isError) {
          errorMessage += ', ';
        }
        errorMessage += 'Revenue Forecast Model';
        isError = true;
      }
      */
      if (proj.psa_forecast_category__c != 'Committed') {
        if (isError) {
          errorMessage += ', ';
        }
        errorMessage += 'Forecast Category is not Committed';
        isError = true;
      }
      /*
      if (proj.PSA_Revenue_Recognition_Model__c == '' || proj.PSA_Revenue_Recognition_Model__c == null) {
        if (isError) {
          errorMessage += ', ';
        }
        errorMessage += 'Revenue Recognition Model';
        isError = true;
      }
      */
      if (proj.PSA_Rate_Classification__c == '' || proj.PSA_Rate_Classification__c == null) {
        if (isError) {
          errorMessage += ', ';
        }
        errorMessage += 'Rate Classification';
        isError = true;
      }
      if (proj.PSA_Director__c == null) {
        if (isError) {
          errorMessage += ', ';
        }
        errorMessage += 'Director';
        isError = true;
      }
      if (proj.PSA_PIA__c == null) {
        if (isError) {
          errorMessage += ', ';
        }
        errorMessage += 'PIA';
        isError = true;
      }
      if (proj.PSA_CIM__C == null) {
        if (isError) {
          errorMessage += ', ';
        }
        errorMessage += 'DM';
        isError = true;
      }
      if (proj.PSA_VP__C == null) {
        if (isError) {
          errorMessage += ', ';
        }
        errorMessage += 'VP';
        isError = true;
      }
      if (proj.pse__Account__c == null) {
        if (isError) {
          errorMessage += ', ';
        }
        errorMessage += 'Billing Account';
        isError = true;
      }
      if (proj.psa_Customer_Account__c == null) {
        if (isError) {
          errorMessage += ', ';
        }
        errorMessage += 'Customer Account';
        isError = true;
      }
      if (proj.PSA_Ship_To_Contact__c == null) {
        if (isError) {
          errorMessage += ', ';
        }
        errorMessage += 'Ship To Contact';
        isError = true;
      }
      if (proj.PSA_Bill_To_Contact__c == null) {
        if (isError) {
          errorMessage += ', ';
        }
        errorMessage += 'Bill To Contact';
        isError = true;
      }
      if (proj.psa_Expense_Approval_Method__c == '' || proj.PSA_Time_Approval_Method__c == null) {
        if (isError) {
          errorMessage += ', ';
        }
        errorMessage += 'Expense Approval Method';
        isError = true;
      }
      if (proj.psa_Time_Approval_Method__c == '' || proj.psa_Time_Approval_Method__c == null) {
        if (isError) {
          errorMessage += ', ';
        }
        errorMessage += 'Time Approval Method';
        isError = true;
      }
  
      if (proj.psa_Services_Product__c == '' || proj.psa_services_product__c == null) {
        if (isError) {
          errorMessage += ', ';
        }
        errorMessage += 'Services Product';
        isError = true;
  
      }
      if (proj.psa_Product_Line__c == '' || proj.psa_Product_Line__c == null) {
        if (isError) {
          errorMessage += ', ';
        }
        errorMessage += 'Product Line';
        isError = true;
      }
      if (proj.PSA_Department__c == null) {
        if (isError) {
          errorMessage += ', ';
        }
        errorMessage += 'Department';
        isError = true;
      }
      if (proj.pse__Project_Manager__c == null) {
        if (isError) {
          errorMessage += ', ';
        }
        errorMessage += 'Project Manager';
        isError = true;
      }
  
      if (isError) {
        proj.addError(errorMessage);
      }
    }
  
    private void validateFinanceReview(pse__Proj__c proj, boolean isCustomer) {
      String errorMessage = 'The following field(s) are missing for Stage: Finance Review: \r\n';
      boolean isError = false;
      if (proj.pse__Project_Manager__c == null) {
        errorMessage += 'Project Manager';
        isError = true;
      }
      if (proj.PSA_Director__c == null) {
        if (isError) {
          errorMessage += ', ';
        }
        errorMessage += 'Director';
        isError = true;
      }
      if (proj.PSA_PIA__c == null) {
        if (isError) {
          errorMessage += ', ';
        }
        errorMessage += 'PIA';
        isError = true;
      }
      if (proj.PSA_CIM__C == null) {
        if (isError) {
          errorMessage += ', ';
        }
        errorMessage += 'DM';
        isError = true;
      }
      if (proj.PSA_Billing_Legal_Entity__c == null) {
        if (isError) {
          errorMessage += ', ';
        }
        errorMessage += 'Billing Legal Entity';
        isError = true;
      }
      if (proj.PSA_Billing_Detail_Template__c == null) {
        if (isError) {
          errorMessage += ', ';
        }
        errorMessage += 'Billing Detail Template';
        isError = true;
      }
      if (proj.PSA_VP__C == null) {
        if (isError) {
          errorMessage += ', ';
        }
        errorMessage += 'VP';
        isError = true;
      }
      if (proj.pse__Account__c == null) {
        if (isError) {
          errorMessage += ', ';
        }
        errorMessage += 'Billing Account';
        isError = true;
      }
      if (proj.psa_Customer_Account__c == null) {
        if (isError) {
          errorMessage += ', ';
        }
        errorMessage += 'Customer Account';
        isError = true;
      }
      if (proj.PSA_Ship_To_Contact__c == null) {
        if (isError) {
          errorMessage += ', ';
        }
        errorMessage += 'Ship To Contact';
        isError = true;
      }
      if (proj.PSA_Bill_To_Contact__c == null) {
        if (isError) {
          errorMessage += ', ';
        }
        errorMessage += 'Bill To Contact';
        isError = true;
      }
      if (proj.psa_Expense_Approval_Method__c == '' || proj.PSA_Time_Approval_Method__c == null) {
        if (isError) {
          errorMessage += ', ';
        }
        errorMessage += 'Expense Approval Method';
        isError = true;
      }
      if (proj.psa_Time_Approval_Method__c == '' || proj.psa_Time_Approval_Method__c == null) {
        if (isError) {
          errorMessage += ', ';
        }
        errorMessage += 'Time Approval Method';
        isError = true;
      }
  
      if (proj.psa_Services_Product__c == '' || proj.psa_services_product__c == null) {
        if (isError) {
          errorMessage += ', ';
        }
        errorMessage += 'Services Product';
        isError = true;
  
      }
      if (proj.psa_Product_Line__c == '' || proj.psa_Product_Line__c == null) {
        if (isError) {
          errorMessage += ', ';
        }
        errorMessage += 'Product Line';
        isError = true;
      }
      if (proj.PSA_Department__c == null) {
        if (isError) {
          errorMessage += ', ';
        }
        errorMessage += 'Department';
        isError = true;
      }
  
      List<PSA_Implementer__c> imps = impMap.get(proj.id);
      if (imps == null || imps.isEmpty()) {
        if (isError) {
          errorMessage += ', ';
        }
        errorMessage += ('Implementers');
        isError = true;
        //throw new psaException('At least one implementer is required for a project to be set to In progress');
      }
      if (isError) {
        proj.addError(errorMessage);
      }
    }
      //@future
      public static void updateRRScheduleDates(list<pse__Resource_Request__c> resourcerequestlist, map<id,pse__Proj__c> projMap){
      //list<pse__Resource_Request__c> resourcerequestlist = new list<pse__Resource_Request__c> ([SELECT pse__Project__c,id, name, pse__Preferred_Schedule__c,pse__Start_Date__c,pse__end_Date__c from pse__Resource_Request__c where id in :resourceRequestObjIds 
      //                          and (pse__Status__c = 'Draft' Or pse__Status__c = 'Hold')]);
      //set<id> projIds = new set<id> ();
          set<Id> scheduleIds = new set<Id> ();
          map<id,pse__Schedule__c> rrScheduleToBeUpdated = new map<id,pse__Schedule__c> ();
      list<pse__Schedule__c> rrScheduleToBeUpdatedList = new list<pse__Schedule__c> ();
      list<pse__Resource_Request__c> resourcerequestToBeUpdatedlist = new list<pse__Resource_Request__c>();
      for (pse__Resource_Request__c rr : resourcerequestlist){
        //projIds.add(rr.pse__Project__c);
              if(rr.pse__Project__r.pse__Project_Type__c == 'Customer Project'){
                scheduleIds.add(rr.pse__Preferred_Schedule__c);
              }
      }
      //map<id,pse__Proj__c> projMap = new map<id, pse__Proj__c> ([Select id, pse__Start_Date__c,pse__end_Date__c from pse__Proj__c where id in: projIds]);
          if(!scheduleIds.isEmpty()){
              rrScheduleToBeUpdated = new map<id,pse__Schedule__c> ([select id, pse__Start_Date__c,pse__End_Date__c from pse__Schedule__c where id in:scheduleIds]);
          }
          
          for (pse__Resource_Request__c rr : resourcerequestlist)
          {
        if(rr.pse__Status__c == 'Draft' || rr.pse__Status__c == 'Hold'){
          if( rr.pse__Start_Date__c != projMap.get(rr.pse__Project__c).pse__Start_Date__c || 
            rr.pse__end_Date__c != projMap.get(rr.pse__Project__c).pse__end_Date__c){
            rr.pse__Start_Date__c = projMap.get(rr.pse__Project__c).pse__Start_Date__c;
            rr.pse__end_Date__c = projMap.get(rr.pse__Project__c).pse__end_Date__c;
            resourcerequestToBeUpdatedlist.add(rr);
            if(!rrScheduleToBeUpdated.isEmpty() && rrScheduleToBeUpdated.containskey(rr.pse__Preferred_Schedule__c))
            {rrScheduleToBeUpdated.get(rr.pse__Preferred_Schedule__c).pse__Start_Date__c = rr.pse__Start_Date__c;
              rrScheduleToBeUpdated.get(rr.pse__Preferred_Schedule__c).pse__end_Date__c = rr.pse__end_Date__c;
              rrScheduleToBeUpdatedList.add(rrScheduleToBeUpdated.get(rr.pse__Preferred_Schedule__c));
            }
          }
        }
  
          }
      if(!resourcerequestToBeUpdatedlist.isEmpty())
          {update resourcerequestToBeUpdatedlist;}
      if(!rrScheduleToBeUpdatedList.isEmpty())
          {update rrScheduleToBeUpdatedList;}
              
  
      }
    public static void UpsertExpenseSharing(list<id> projIDs){

        if(runningInFutureContext()){
          syncUpsertExpenseSharing(projIDs);
        } 
        else{
          asyncUpsertExpenseSharing(projIDs);
        } 
      }

    @future
    public static void asyncUpsertExpenseSharing(list<id> projIDs){
        syncUpsertExpenseSharing(projIDs);
    }

    public static void syncUpsertExpenseSharing(list<id> projIDs){
        psaTriggerMonitor.ExecutedTriggers.add('UpsertExpenseSharing');
        list<pse__Expense__share> expenseSharingList = new list<pse__Expense__share> ();
        list<pse__Expense__c> expenseList = [select pse__Project__r.pse__Project_Manager__r.pse__Salesforce_User__c,pse__Project__r.PSA_CIM__r.pse__Salesforce_User__c,
                                            pse__Project__r.PSA_Director__r.pse__Salesforce_User__c,pse__Project__r.PSA_VP__r.pse__Salesforce_User__c,pse__Expense_Report__r.pse__Approver__r.delegatedapproverId,
                                            pse__Project__r.PSA_Expense_Approval_Method__c, pse__Resource__r.pse__Salesforce_User__r.ManagerId from pse__Expense__c 
                                            where pse__Project__c in :projIDs] ;

        for(pse__Expense__c exp: expenseList){
            pse__Expense__share expShareRecord = new pse__Expense__share();
            expShareRecord.ParentId = exp.Id;
            expShareRecord.UserOrGroupId = exp.pse__Project__r.PSA_CIM__r.pse__Salesforce_User__c;
            expShareRecord.AccessLevel = 'Read';
            expShareRecord.RowCause = Schema.pse__Expense__share.RowCause.pse__PSE_Member_Share__c;
            expenseSharingList.add(expShareRecord);
            expShareRecord = new pse__Expense__share();
            expShareRecord.ParentId = exp.Id;
            expShareRecord.UserOrGroupId = exp.pse__Project__r.PSA_Director__r.pse__Salesforce_User__c;
            expShareRecord.AccessLevel = 'Read';
            expShareRecord.RowCause = Schema.pse__Expense__share.RowCause.pse__PSE_Member_Share__c;
            expenseSharingList.add(expShareRecord);
            expShareRecord = new pse__Expense__share();
            expShareRecord.ParentId = exp.Id;
            expShareRecord.UserOrGroupId = exp.pse__Project__r.PSA_VP__r.pse__Salesforce_User__c;
            expShareRecord.AccessLevel = 'Read';
            expShareRecord.RowCause = Schema.pse__Expense__share.RowCause.pse__PSE_Member_Share__c;
            expenseSharingList.add(expShareRecord);
            expShareRecord = new pse__Expense__share();
            expShareRecord.ParentId = exp.Id;
            expShareRecord.UserOrGroupId = exp.pse__Project__r.pse__Project_Manager__r.pse__Salesforce_User__c;
            expShareRecord.AccessLevel = 'Read';
            expShareRecord.RowCause = Schema.pse__Expense__share.RowCause.pse__PSE_Member_Share__c;
            expenseSharingList.add(expShareRecord);
            //if(exp.pse__Project__r.PSA_Expense_Approval_Method__c == 'Resource Manager'){
                expShareRecord = new pse__Expense__share();
                expShareRecord.ParentId = exp.Id;
                expShareRecord.UserOrGroupId = exp.pse__Resource__r.pse__Salesforce_User__r.ManagerId;
                expShareRecord.AccessLevel = 'Read';
                expShareRecord.RowCause = Schema.pse__Expense__share.RowCause.pse__PSE_Member_Share__c;
                expenseSharingList.add(expShareRecord);
    
            //}

            if(exp.pse__Expense_Report__r.pse__Approver__r.delegatedapproverId != null){
                expShareRecord = new pse__Expense__share();
                expShareRecord.ParentId = exp.Id;
                expShareRecord.UserOrGroupId = exp.pse__Expense_Report__r.pse__Approver__r.delegatedapproverId;
                expShareRecord.AccessLevel = 'Read';
                expShareRecord.RowCause = Schema.pse__Expense__share.RowCause.pse__PSE_Member_Share__c;    
                expenseSharingList.add(expShareRecord);
            }
        }
        if(expenseSharingList.size()>0){
            Database.upsert(expenseSharingList, false);
        }

    }
    private static Boolean runningInFutureContext(){
        return (System.isFuture() || System.isBatch());
      }
}