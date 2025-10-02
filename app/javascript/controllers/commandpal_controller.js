import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    connect() {
        console.log("commandpal controller connected");
        // Get the value of field current_entity_type
        let current_entity_type = document.getElementById("current_entity_type").value;
        let commands = [];
        // If the current entity type has Fund in it, then show the fund management commands
        if (current_entity_type.includes("Fund")) {
            commands = this.fm_keys();
            this.add_menus(commands);
        }
        if (commands.length > 0) {
          const c = new CommandPal({
              hotkey: "ctrl+space",
              commands: commands,
          });
          c.start();
        }
    }

    add_menus(commands) {
        // Read the commands from the page element called hotkeys
        // Format is parent => name: shortcut: handler, name: shortcut: handler; parent => name: shortcut: handler, name: shortcut: handler
        let hotkeys = $("#hotkeys").val();
        let hotkeys_parent = $("#hotkeys_parent").val();


        if(hotkeys) {
          let hotkey_list = hotkeys.split(";");
          let children = []
          for (let i = 0; i < hotkey_list.length; i++) {
              let hotkey = hotkey_list[i].split(":");
              let name = hotkey[0];
              // let shortcut = hotkey[1];
              let loc = hotkey[1];
              let child = {
                  name: name,
                  // shortcut: shortcut,
                  handler: () => { window.location = loc; }
              }
              children.push(child);
          }
          // Add this to the front of the commands list
          let command = {
            name: hotkeys_parent,
            shortcut: "ctrl+1",
            children: children,
          }
          commands.unshift(command);
        }
    }

    fm_keys() {
      let children = [
        {
            name: "Funds",
            shortcut: "ctrl+u",
            handler: () => {
                window.location = "/funds";
            }
        },
        {
            name: "All Reports",
            shortcut: "ctrl+shift+a",
            handler: () => {
                window.location = "/reports";
            }
        },
        {
            name: "Stakeholders",
            shortcut: "ctrl+s",
            handler: () => {
                window.location = "/investors";
            }
        },
        {
            name: "Approvals",
            shortcut: "ctrl+a",
            handler: () => {
                window.location = "/approvals";
            }
        },
        {
            name: "Documents",
            shortcut: "ctrl+d",
            handler: () => {
                window.location = "/documents";
            }
        },

        {
          name: "Layouts",
          shortcut: "ctrl+l",
          handler: () => { this.layouts(); }
        },

        {
            name: "Opportunities",
            shortcut: "ctrl+o",
            handler: () => {
                window.location = "/investment_opportunities";
            }
        },

        {
            name: "KYCs",
            shortcut: "ctrl+k",
            handler: () => {  window.location = "/investor_kycs"; }
          },

          {
            name: "Misc",
            shortcut: "ctrl+m",
            children: this.misc()
          },
        ];

      // Get the path part of the URL
      const path = window.location.pathname;

      // We have a mapping of path to report_category
      let report_categories = {
        "account_entries": "Account Entries",
        "capital_commitments": "Commitments",
        "capital_remittances": "Remittances",
        "kpis": "Kpis",
        "investor_kycs": "KYCs",
        "portfolio_investments": "Portfolio Investments",
        "aggregate_portfolio_investments": "Aggregate Portfolio Investments",
        "capital_distributions": "Distributions",
      }

      // If the path is in the mapping, add a report menu
      let report_category = report_categories[path.split("/")[1]];

      if (report_category) {
        // Add it to the children list at index 1
        children.splice(2, 0,
          {
            name: report_category + " Reports",
            shortcut: "ctrl+shift+r",
            handler: () => {
                  window.location = "/reports?category=" + report_category;
            }
          }
        );
      }

      return children;
    }

    layouts() {

      // Programmatically open the offcanvas for theme chooser
      const offcanvasElement = document.getElementById("settings-offcanvas");
      if (offcanvasElement) {
        const bsOffcanvas = bootstrap.Offcanvas.getOrCreateInstance(offcanvasElement);
        bsOffcanvas.show();
      }

    }

    misc() {
      // Get the path part of the URL
      const path = window.location.pathname;

      let children = [
        {
          name: "Notifications",
          handler: () => {  window.location = "/notifications"; }
        },
        {
          name: "Uploads",
          handler: () => {  window.location = "/import_uploads"; }
        },
        {
          name: "Tasks",
          handler: () => {  window.location = "/tasks"; }
        },
        {
          name: "Logout",
          // Click on the Logout button
          handler: () => {
            console.log("Logging out");
            const logoutButton = document.getElementById('logout');
            if (logoutButton) {
                logoutButton.click();
            }
          }
        }
      ]

      // Regular expression to match the pattern /resource/resource_id where resource_id is an integer
      const regex = /^\/[a-zA-Z_]+\/\d+$/;

      // Test if the path matches the pattern
      const matches = regex.test(path);

      // alert(matches);
      // alert(path);

      if (matches) {
        console.log('The URL follows the pattern /resource/resource_id');
        children.unshift(
          {
            name: "Calendar",
            // from the url, get the path and id and use that to create the calendar url
            handler: () => {
              let url = new URL(window.location.href);
              let path = url.pathname.split("/")[1];
              let id = url.pathname.split("/").pop();
              window.location = "/events?owner_type=" + path + "&owner_id=" + id;
            }
          }
        );
        children.unshift(
          {name: "Audit Trail",
            // Add the parameter audit_trail=true to the existing URL and reload the page
            handler: () => {
              let url = new URL(window.location.href);
              url.searchParams.set('audit_trail', 'true');
              window.location = url;
            }
          }
        );
        children.unshift(
          {name: "Compliance Checks",
            // Add the parameter audit_trail=true to the existing URL and reload the page
            handler: () => {
              let url = new URL(window.location.href);
              url.searchParams.set('ai_checks', 'true');
              url.searchParams.set('rule_type', 'compliance');
              window.location = url;
            }
          }
        );
      } else {
        console.log('The URL does not match the pattern');
        children.unshift(
          {
            name: "Filter",
            // Add the parameter filter=true to the existing URL and reload the page
            handler: () => {
              let url = new URL(window.location.href);
              url.searchParams.set('filter', 'true');
              window.location = url;
            }
          }
        );
      }



      return children;

    }


}


